-- Wox settings kept under version control.
-- Regenerate with `wox-cfg-export`, apply with `wox-cfg-import` (shell-cfg.sh).
-- Booleans are stored by Wox as plain 'true'/'false' strings.

-- Anonymous usage telemetry: daily presence ping to wox-telemetry.qlf.workers.dev.
INSERT OR REPLACE INTO wox_settings(key,value) VALUES('EnableAnonymousUsageStats','false');

-- File Search: its FSEvents indexer re-scans the whole home directory in a loop
-- when a busy tree (e.g. a local ClickHouse data volume) overflows the event
-- queue, pinning a CPU core.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('979d6363-025a-4f51-88d3-0b04e9dc56bf','Disabled','true');

-- Clipboard History: keeps copied text (including credentials) in plain text
-- inside wox.db and clipboard.db.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('5f815d98-27f5-488d-a756-c317ea39935b','Disabled','true');

-- Converter: polls exchange rates (HKAB) and crypto prices (CoinGecko) on a
-- schedule in the background.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('a48dc5f0-dab9-4112-b883-b68129d6782b','Disabled','true');

-- Browser Bookmarks: sends every bookmarked domain to Google's favicon service
-- at startup.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('95d041d3-be7e-4b20-8517-88dda2db280b','Disabled','true');

-- URL: sends domains from the recent URL history to Google's favicon service
-- at startup.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('1af58721-6c97-4901-b291-620daf08d9c9','Disabled','true');

-- Browser: listens on 127.0.0.1:34988 for the browser extension and fetches
-- favicons from Google on every tab update.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('8f68a760-86a0-46a9-b331-58dcaf091daa','Disabled','true');

-- Screenshot: decodes and resizes its whole capture history at startup.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('78fc701b-a87e-4d5f-a7f2-13cbad9f7d1d','Disabled','true');

-- Media Player: keeps a 1 Hz ticker alive that cannot be stopped without a restart.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('b8f3d4e5-6c7a-4b9c-8d1e-2f3a4b5c6d7e','Disabled','true');

-- Quick Jump: installs a global keyboard tap while Finder or a file dialog is active.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('6cde8bec-3f19-44f6-8a8b-d3ba3712d04e','Disabled','true');

-- Dictation: runs idle reaper tickers even when dictation is never used.
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('a3f7b8c2-d1e4-4f6a-9b0c-7e2d1a5f8b3e','Disabled','true');
