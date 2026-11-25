// Pings a host 5 times a second with the system ping: gnome-shell can't
// send ICMP itself, and ping needs no privileges on Fedora

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const RESTART_MS = 1000;

export class Pinger {
  constructor(maxLen) {
    this._maxLen = maxLen;
    this._host = null;
    this._proc = null;
    this._restartTimer = null;
    // Sequence numbers start anew with each ping process
    this._run = 0;
    // {seq, ms}, ms is null until a reply
    this.history = [];
  }

  setHost(host) {
    if (host === this._host) {
      return;
    }
    this._host = host;
    this.history = [];
    this._stop();
    if (host) {
      this._start();
    }
  }

  destroy() {
    this._host = null;
    this._stop();
  }

  // Called on each sample: ping exits on start without a network and
  // reports nothing until it is restarted, which is shown as lost packets
  tick() {
    if (this._host && !this._proc) {
      this._push({seq: null, ms: null});
    }
  }

  _start() {
    this._run++;
    // -O reports a packet with no reply before sending the next one
    this._proc = Gio.Subprocess.new(
      ['ping', '-O', '-n', '-i', '0.2', this._host],
      Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE);
    this._cancellable = new Gio.Cancellable();
    const stdout = new Gio.DataInputStream({
      base_stream: this._proc.get_stdout_pipe(),
      close_base_stream: true,
    });
    this._readLine(this._proc, stdout, this._cancellable);
  }

  _stop() {
    if (this._restartTimer) {
      GLib.source_remove(this._restartTimer);
      this._restartTimer = null;
    }
    if (this._proc) {
      this._cancellable.cancel();
      this._proc.force_exit();
      this._proc = null;
    }
  }

  _readLine(proc, stdout, cancellable) {
    stdout.read_line_async(GLib.PRIORITY_DEFAULT, cancellable, (s, res) => {
      let line;
      try {
        [line] = s.read_line_finish_utf8(res);
      } catch (e) {
        if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED)) {
          logError(e);
        }
        return;
      }
      if (line === null) {
        this._onExit(proc);
        return;
      }
      this._onLine(line);
      this._readLine(proc, stdout, cancellable);
    });
  }

  _onExit(proc) {
    if (proc !== this._proc) {
      return;
    }
    this._proc = null;
    this._restartTimer = GLib.timeout_add(
      GLib.PRIORITY_DEFAULT, RESTART_MS, () => {
        this._restartTimer = null;
        if (this._host) {
          this._start();
        }
        return GLib.SOURCE_REMOVE;
      });
  }

  // "64 bytes from 1.1.1.1: icmp_seq=3 ttl=57 time=7.53 ms",
  // "no answer yet for icmp_seq=1", "From 10.0.0.1 icmp_seq=1 Packet
  // filtered". A late reply fills the packet reported as lost.
  _onLine(line) {
    const num = line.match(/icmp_seq=(\d+)/)?.[1];
    if (num === undefined) {
      // "ping: sendmsg: Network is unreachable" when the network is lost
      if (line.startsWith('ping: ')) {
        this._push({seq: null, ms: null});
      }
      return;
    }
    const seq = `${this._run}:${num}`;
    const ms = line.match(/time=([\d.]+) ms/)?.[1];
    const item = this.history.find(i => i.seq === seq);
    if (item) {
      item.ms ??= ms === undefined ? null : Number(ms);
      return;
    }
    this._push({seq, ms: ms === undefined ? null : Number(ms)});
  }

  _push(item) {
    this.history.push(item);
    if (this.history.length > this._maxLen) {
      this.history.shift();
    }
  }
}
