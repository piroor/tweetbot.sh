# tweetbot.sh, a Twitter bot program written in simple Bash script

## Setup

You need to prepare API keys at first.
Go to [the front page](https://apps.twitter.com/), create a new app, and generate a new access token.
Then put them as a key file at `~/.tweet.client.key`, with the format:

~~~
CONSUMER_KEY=xxxxxxxxxxxxxxxxxxx
CONSUMER_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ACCESS_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ACCESS_TOKEN_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
~~~

If there is a key file named `tweet.client.key` in the current directory, `tweet.sh` will load it.
Otherwise, the file `~/.tweet.client.key` will be used as the default key file.

Moreover, you can give those information via environment variables without a key file.

~~~
$ export CONSUMER_KEY=xxxxxxxxxxxxxxxxxxx
$ export CONSUMER_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
$ export ACCESS_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
$ export ACCESS_TOKEN_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
$ ./watch.sh
~~~

## Usage

~~~
$ ./watch.sh
~~~

You don't have to specify any option.
This program automatically detects required data files from the base directory, it is same to the working (current) directory by default.
The base directory can be supplied via an environment variable `TWEET_BASE_DIR`, like:

~~~
$ env TWEET_BASE_DIR=/home/username/data /path/to/watch.sh
~~~

## data files

This script detects data files and directories from the base directory.
The base directory should have these files:

 * `$TWEET_BASE_DIR/queries.txt`: a list of search keywords to be watched.
 * `$TWEET_BASE_DIR/responses`: a directory to put response messages.
 * `$TWEET_BASE_DIR/logs`: a blank directory to store logs.