Script to Update FRP


Demo Output:

```
root@Debian-93-stretch-64-LAMP /opt/frp # ./update-frp.sh

=================================
      FRP Update Utility
=================================

Select component:
  1) frps (Server)
  2) frpc (Client)

Selection [1-2]: 1

Checking installed version...
Installed version : 0.68.1

Checking latest release...
Latest version    : 0.69.1

Press ENTER to install latest or type version [0.69.1]: 

Selected version  : 0.69.1

Component         : frps
Service           : frps.service
Download URL      : https://github.com/fatedier/frp/releases/download/v0.69.1/frp_0.69.1_linux_amd64.tar.gz

Continue update? [y/N]: y

Creating backup...
Downloading...
--2026-06-03 08:50:05--  https://github.com/fatedier/frp/releases/download/v0.69.1/frp_0.69.1_linux_amd64.tar.gz
Resolving github.com (github.com)... 140.82.121.4
Connecting to github.com (github.com)|140.82.121.4|:443... connected.
HTTP request sent, awaiting response... 302 Found
Location: https://release-assets.githubusercontent.com/github-production-release-asset/48378947/58fb1629-c71b-44ef-800b-54aecbed0939?sp=r&sv=2018-11-09&sr=b&spr=https&se=2026-06-03T07%3A39%3A59Z&rscd=attachment%3B+filename%3Dfrp_0.69.1_linux_amd64.tar.gz&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2026-06-03T06%3A39%3A51Z&ske=2026-06-03T07%3A39%3A59Z&sks=b&skv=2018-11-09&sig=I7xuEOLSWKtwrk0YHUzGzD2YAoVOZSym6UUjBTW%2Fc9A%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc4MDQ3MTIwNSwibmJmIjoxNzgwNDY5NDA1LCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.kAixrIQ_016GNa8ZG-TEdpsyDkczXgZvVLU7wJTCre0&response-content-disposition=attachment%3B%20filename%3Dfrp_0.69.1_linux_amd64.tar.gz&response-content-type=application%2Foctet-stream [following]
--2026-06-03 08:50:05--  https://release-assets.githubusercontent.com/github-production-release-asset/48378947/58fb1629-c71b-44ef-800b-54aecbed0939?sp=r&sv=2018-11-09&sr=b&spr=https&se=2026-06-03T07%3A39%3A59Z&rscd=attachment%3B+filename%3Dfrp_0.69.1_linux_amd64.tar.gz&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2026-06-03T06%3A39%3A51Z&ske=2026-06-03T07%3A39%3A59Z&sks=b&skv=2018-11-09&sig=I7xuEOLSWKtwrk0YHUzGzD2YAoVOZSym6UUjBTW%2Fc9A%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc4MDQ3MTIwNSwibmJmIjoxNzgwNDY5NDA1LCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.kAixrIQ_016GNa8ZG-TEdpsyDkczXgZvVLU7wJTCre0&response-content-disposition=attachment%3B%20filename%3Dfrp_0.69.1_linux_amd64.tar.gz&response-content-type=application%2Foctet-stream
Resolving release-assets.githubusercontent.com (release-assets.githubusercontent.com)... 185.199.111.133, 185.199.109.133, 185.199.110.133, ...
Connecting to release-assets.githubusercontent.com (release-assets.githubusercontent.com)|185.199.111.133|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 14189005 (14M) [application/octet-stream]
Saving to: ‘frp_0.69.1_linux_amd64.tar.gz’

frp_0.69.1_linux_amd64.tar.gz                          100%[=========================================================================================================================>]  13.53M  65.7MB/s    in 0.2s    

2026-06-03 08:50:06 (65.7 MB/s) - ‘frp_0.69.1_linux_amd64.tar.gz’ saved [14189005/14189005]

Extracting...
Stopping service...
Installing...
Starting service...

Checking service...
SUCCESS: Service is running.

Done.
Backup: /opt/frp_backup_2026-06-03_08-50-05

root@Debian-93-stretch-64-LAMP /opt/frp #
```
