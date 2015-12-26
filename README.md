# tweetbot.sh, a Twitter bot program written in simple Bash script

## How works?

This bot watches events around the related your Twitter account, and will react to them.

 * If someone follows you, this will follows him/her.
 * If someone mentioned to you, this will...
   * favorite it.
   * respond to it, if you supplied response messages.
 * If someone retweeted your tweet with comments, this will...
   * favorite it.
   * retweet it.
   * respond to it, if it is a mention to you and you supplied response messages.
 * If someone posted tweets including keywords you specified, this will...
   * favorite it.
   * retweet it.

## Setup

You need to prepare API keys at first.
Go to [the front page](https://apps.twitter.com/), create a new app, and generate a new access token.

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

## Contents of the base directory

This script detects data files and directories from the base directory (the current directory or the directory specified via an environment variable `TWEET_BASE_DIR`).
The base directory should have them:

 * `$TWEET_BASE_DIR/tweet.client.key`: the definition of API keys. This is always required.
 * `$TWEET_BASE_DIR/queries.txt` (optional): a list of search keywords to be watched.
 * `$TWEET_BASE_DIR/responses` (optional): a directory to put response messages.
 * `$TWEET_BASE_DIR/logs` (optional): a blank directory to store logs.

### `tweet.client.key`

Put [informations of a generated API key](https://apps.twitter.com/), with the format:

~~~
CONSUMER_KEY=xxxxxxxxxxxxxxxxxxx
CONSUMER_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ACCESS_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ACCESS_TOKEN_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
~~~


### `queries.txt`

Put keywords to be watched, with the format:

~~~
Bash
Shell Script
Twitter
~~~

You should put one phrase per one line.
They are treated like conditions with the `OR` logical operator.
Any tweet matched to one of given terms will be favorited and retweeted.

This file must be encoded in UTF-8.


### `responses`

The `responses` directory will contain response message definition files.
Each definition file includes both keywords to be detected and messages to be responded, with the format:

~~~
# hello
# hi|hey
# good (morning|afternoon|evening)

Hi!
Hello!
Aloha!
Ola!
~~~

Lines beginning with `#` are defines keywords.
Others defines response messages.
If one of keyword matches to the body of the mention, one of following messages (chosen at random) will be postead as a reply.
A definition file including no keyword definition will be simply ignored.

Keywords are treated as extended regular expressions.
Meta characters will have to be escaped.

This file must be encoded in UTF-8.


### `logs`

Logs will be stored into the directory.
Even if you don't prepare it, it will be created automatically.

