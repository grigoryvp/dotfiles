// Router ping, internet ping and CPU load graphs in the top panel, the same
// as hammerspoon/main.lua draws in the macOS menu bar. Runs inside
// gnome-shell, so it must stay cheap: samples are taken 5 times a second,
// while the graphs are redrawn once.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import * as graph from './graph.js';
import {Pinger} from './pinger.js';

const SAMPLE_MS = 200;
const SAMPLES_PER_DRAW = 5;
// Reading the route every sample is a waste, while a network change is
// rare and noticed by the router ping anyway
const SAMPLES_PER_ROUTE_CHECK = 50;
// Only constant CPU load is of interest, so its history is shorter
const MAX_CPU_SAMPLES = 10;
const MAX_PING_SAMPLES = 20;
const HEIGHT = 20;
const INET_HOST = '1.1.1.1';

const CPU_RANGES = [
  [0.10, graph.GREEN],
  [0.20, graph.YELLOW],
  [0.50, graph.ORANGE],
  [1.00, graph.RED],
];

const PING_RANGES = [
  [50, graph.GREEN],
  [200, graph.YELLOW],
  [500, graph.ORANGE],
  [2000, graph.RED],
];

const decoder = new TextDecoder();

function readFile(path) {
  const [, bytes] = GLib.file_get_contents(path);
  return decoder.decode(bytes);
}

// Busy and idle jiffies of all CPUs, from the first line of /proc/stat:
// "cpu user nice system idle iowait irq softirq steal ..."
function readTicks() {
  const text = readFile('/proc/stat');
  const fields = text.slice(0, text.indexOf('\n')).split(/\s+/).slice(1, 9)
    .map(Number);
  const [user, nice, system, idle, iowait, irq, softirq, steal] = fields;
  return {
    busy: user + nice + system + irq + softirq + steal,
    idle: idle + iowait,
  };
}

// The gateway of the IPv4 default route with the lowest metric, or null.
// /proc/net/route has the main table only, so Tailscale's routes, which
// live in a table of their own, don't hide the router.
function readGateway() {
  let best = null;
  for (const line of readFile('/proc/net/route').split('\n').slice(1)) {
    const [, dest, gateway, , , , metric, mask] = line.split(/\s+/);
    if (dest !== '00000000' || mask !== '00000000' || !gateway) {
      continue;
    }
    if (!best || Number(metric) < best.metric) {
      best = {gateway, metric: Number(metric)};
    }
  }
  if (!best || best.gateway === '00000000') {
    return null;
  }
  // Little-endian hex: "0108A8C0" is 192.168.8.1
  return best.gateway.match(/../g).reverse()
    .map(byte => parseInt(byte, 16)).join('.');
}

function cpuBars(history) {
  return [...history].reverse().map(
    load => graph.scaled(load, CPU_RANGES) ?? {val: 1, color: graph.RED});
}

// A lost packet or a reply after 2 seconds, which is as bad as no internet,
// is a grey bar of a height that changes on each redraw, for a visual "in
// progress" feedback
function pingBars(history, drawCount) {
  return [...history].reverse().map((item, i) => {
    const bar = item.ms === null ? null : graph.scaled(item.ms, PING_RANGES);
    return bar ?? {
      val: (drawCount + i) % 2 === 0 ? 0.2 : 0.4,
      color: graph.GREY,
    };
  });
}

export default class GraphsExtension extends Extension {
  enable() {
    this._cpuHistory = [];
    this._sampleCount = 0;
    this._drawCount = 0;
    this._lastTicks = readTicks();
    this._routerPinger = new Pinger(MAX_PING_SAMPLES);
    this._inetPinger = new Pinger(MAX_PING_SAMPLES);
    this._routerPinger.setHost(readGateway());
    this._inetPinger.setHost(INET_HOST);

    this._button = new PanelMenu.Button(0.0, this.metadata.name, true);
    const box = new St.BoxLayout({style: 'spacing: 4px;'});
    const area = (maxSamples, getBars) => {
      const result = new St.DrawingArea({
        width: maxSamples * graph.BAR_WIDTH + 2,
        height: HEIGHT,
        y_align: Clutter.ActorAlign.CENTER,
      });
      result.connect('repaint', a => graph.draw(a, getBars()));
      box.add_child(result);
      return result;
    };
    this._areas = [
      area(MAX_PING_SAMPLES,
        () => pingBars(this._routerPinger.history, this._drawCount)),
      area(MAX_PING_SAMPLES,
        () => pingBars(this._inetPinger.history, this._drawCount)),
      area(MAX_CPU_SAMPLES, () => cpuBars(this._cpuHistory)),
    ];
    this._button.add_child(box);
    Main.panel.addToStatusArea(this.uuid, this._button, 0, 'right');

    this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SAMPLE_MS, () => {
      this._sample();
      return GLib.SOURCE_CONTINUE;
    });
  }

  disable() {
    GLib.source_remove(this._timer);
    this._timer = null;
    this._routerPinger.destroy();
    this._routerPinger = null;
    this._inetPinger.destroy();
    this._inetPinger = null;
    this._button.destroy();
    this._button = null;
    this._areas = null;
    this._cpuHistory = null;
  }

  _sample() {
    const ticks = readTicks();
    const busy = ticks.busy - this._lastTicks.busy;
    const idle = ticks.idle - this._lastTicks.idle;
    this._lastTicks = ticks;
    this._cpuHistory.push(busy + idle > 0 ? busy / (busy + idle) : 0);
    if (this._cpuHistory.length > MAX_CPU_SAMPLES) {
      this._cpuHistory.shift();
    }
    this._routerPinger.tick();
    this._inetPinger.tick();

    this._sampleCount++;
    if (this._sampleCount % SAMPLES_PER_ROUTE_CHECK === 0) {
      this._routerPinger.setHost(readGateway());
    }
    if (this._sampleCount % SAMPLES_PER_DRAW === 0) {
      this._drawCount++;
      for (const a of this._areas) {
        a.queue_repaint();
      }
    }
  }
}
