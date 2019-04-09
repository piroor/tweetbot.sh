# How to setup

This addon requires the [node wrapper native messaging host](https://github.com/andy-portmen/native-client/releases).

1. Install the node wrapper native messaging host.
2. Add `tweetbotsh-remote-controller@piro.sakura.ne.jp` to the array of `allowed_extensions` in `manifest-firefox.json`. It will be placed at:
   * `C:\Users\(username)\AppData\Local\com.add0n.node\manifest-firefox.json` on Windows.
3. Install required software for `tweet.sh` and put `.tweet.cliekt.key` to your home directory.
   * on Windows:
     1. Install Ubuntu for WSL.
     2. `sudo apt install nkf jq`
     3. Put `.tweet.cliekt.key` to `~/` of the WSL environment.
4. Set path to the file `tweet.sh`.
   * on Windows, you need to specify the path to `tweet.sh` in WSL environment. For example: `/mnt/c/Users/(username)/Documents/tweet.sh/tweet.sh`
