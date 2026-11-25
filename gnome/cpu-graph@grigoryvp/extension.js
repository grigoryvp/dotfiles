// CPU load graph in the top panel, the same as hammerspoon/main.lua draws in
// the macOS menu bar. Runs inside gnome-shell, so it must stay cheap: the
// load is sampled 5 times a second, while the graph is redrawn once.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const SAMPLE_MS = 200;
const SAMPLES_PER_DRAW = 5;
// Only constant load is of interest, so the history is short
const MAX_SAMPLES = 10;
const BAR_WIDTH = 2;
const HEIGHT = 20;

const decoder = new TextDecoder();

// Busy and idle jiffies of all CPUs, from the first line of /proc/stat:
// "cpu user nice system idle iowait irq softirq steal ..."
function readTicks() {
  const [, bytes] = GLib.file_get_contents('/proc/stat');
  const text = decoder.decode(bytes);
  const fields = text.slice(0, text.indexOf('\n')).split(/\s+/).slice(1, 9)
    .map(Number);
  const [user, nice, system, idle, iowait, irq, softirq, steal] = fields;
  return {
    busy: user + nice + system + irq + softirq + steal,
    idle: idle + iowait,
  };
}

// Bar height (0..1) and color: each load range takes a quarter of the
// height, so a light load is still visible
function bar(load) {
  const ranges = [
    [0.10, [0, 1, 0]],
    [0.20, [1, 1, 0]],
    [0.50, [1, 0.5, 0]],
    [1.00, [1, 0, 0]],
  ];
  let low = 0;
  for (const [i, [high, color]] of ranges.entries()) {
    if (load < high || i === ranges.length - 1) {
      const part = Math.min((load - low) / (high - low), 1);
      return {val: (part + i) / ranges.length, color};
    }
    low = high;
  }
  throw new Error('unreachable');
}

export default class CpuGraphExtension extends Extension {
  enable() {
    this._history = [];
    this._sampleCount = 0;
    this._lastTicks = readTicks();

    this._button = new PanelMenu.Button(0.0, this.metadata.name, true);
    this._area = new St.DrawingArea({
      width: MAX_SAMPLES * BAR_WIDTH + 2,
      height: HEIGHT,
      y_align: Clutter.ActorAlign.CENTER,
    });
    this._area.connect('repaint', area => this._draw(area));
    this._button.add_child(this._area);
    Main.panel.addToStatusArea(this.uuid, this._button, 0, 'right');

    this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SAMPLE_MS, () => {
      this._sample();
      return GLib.SOURCE_CONTINUE;
    });
  }

  disable() {
    GLib.source_remove(this._timer);
    this._timer = null;
    this._button.destroy();
    this._button = null;
    this._area = null;
    this._history = null;
  }

  _sample() {
    const ticks = readTicks();
    const busy = ticks.busy - this._lastTicks.busy;
    const idle = ticks.idle - this._lastTicks.idle;
    this._lastTicks = ticks;
    this._history.push(busy + idle > 0 ? busy / (busy + idle) : 0);
    if (this._history.length > MAX_SAMPLES) {
      this._history.shift();
    }
    this._sampleCount++;
    if (this._sampleCount % SAMPLES_PER_DRAW === 0) {
      this._area.queue_repaint();
    }
  }

  _draw(area) {
    const cr = area.get_context();
    const [width, height] = area.get_surface_size();
    cr.setSourceRGB(0, 0, 0);
    cr.rectangle(0, 0, width, height);
    cr.fill();
    cr.setSourceRGB(0.5, 0.5, 0.5);
    cr.setLineWidth(1);
    cr.rectangle(0.5, 0.5, width - 1, height - 1);
    cr.stroke();
    // Newest first, on the left
    const loads = [...this._history].reverse();
    for (const [i, load] of loads.entries()) {
      const {val, color} = bar(load);
      // Whole pixels: a fractional top is drawn blurred
      const barHeight = Math.round(
        Math.min(Math.max(val * (height - 2), 2), height - 2));
      cr.setSourceRGB(...color);
      cr.rectangle(1 + i * BAR_WIDTH, height - 1 - barHeight,
        BAR_WIDTH, barHeight);
      cr.fill();
    }
    cr.$dispose();
  }
}
