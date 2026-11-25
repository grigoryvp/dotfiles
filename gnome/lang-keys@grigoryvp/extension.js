// GNOME has shortcuts only to cycle input sources, not to pick one. keyd
// calls Activate() on m1-shift-f/d/s (see keyd.conf). The panel indicator
// is hidden: GNOME has no setting for it.

import Gio from 'gi://Gio';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
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
    // The indicator shows and hides itself, not its container. The panel
    // shows all containers back on a session mode change, e.g. unlock.
    this._hideIndicator();
    Main.sessionMode.connectObject(
      'updated', () => this._hideIndicator(), this);
  }

  disable() {
    Main.sessionMode.disconnectObject(this);
    Main.panel.statusArea.keyboard?.container.show();
    this._dbus.unexport();
    this._dbus = null;
  }

  _hideIndicator() {
    Main.panel.statusArea.keyboard?.container.hide();
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
