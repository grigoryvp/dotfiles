// GNOME has shortcuts only to cycle input sources, not to pick one. keyd
// calls Activate() on m1-shift-f/d/s (see keyd.conf).

import Gio from 'gi://Gio';
import {getInputSourceManager} from 'resource:///org/gnome/shell/ui/status/keyboard.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IFACE = `
<node>
  <interface name="org.gnome.Shell.Extensions.LangKeys">
    <method name="Activate">
      <arg type="s" direction="in" name="id"/>
    </method>
  </interface>
</node>`;

export default class LangKeysExtension extends Extension {
  enable() {
    this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
    this._dbus.export(
      Gio.DBus.session, '/org/gnome/Shell/Extensions/LangKeys');
  }

  disable() {
    this._dbus.unexport();
    this._dbus = null;
  }

  // Input source id: "us" for xkb, "mozc-jp" for ibus
  Activate(id) {
    const sources = getInputSourceManager().inputSources;
    const source = Object.values(sources).find(s => s.id === id);
    if (!source) {
      throw new Error(`Unknown input source ${id}`);
    }
    source.activate(true);
  }
}
