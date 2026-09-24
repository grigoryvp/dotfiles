-- Disable the built-in File Search plugin: ClickHouse and 100% cpu load
INSERT OR REPLACE INTO plugin_settings(plugin_id,key,value) VALUES('979d6363-025a-4f51-88d3-0b04e9dc56bf','Disabled','true');
