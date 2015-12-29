# tweetbot.sh, a Twitter bot program written in simple Bash script

## How works?

This bot watches events around the related your Twitter account, and will react to them.

 * If someone follows you, this will follows him/her.
 * If someone mentioned to you, this will...
   * favorite it.
   * retweet it. (disabled by default)
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

If you hope to use DMs to control the running bot, you have to permit the app to access direct messages.

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
 * `$TWEET_BASE_DIR/personality.txt` (optional): configures the strategy of the bot.
 * `$TWEET_BASE_DIR/queries.txt` (optional): a list of search keywords to be watched.
 * `$TWEET_BASE_DIR/responses` (optional): a directory to put response messages.

If you permit accessing to direct messages for the app, you'll prepare following files also:

 * `$TWEET_BASE_DIR/administrators.txt` (optional): a list of administrator accounts.
 * `$TWEET_BASE_DIR/on_response_modified.*` (optional): a callback script to be executed when response messages are changed dynamically.
 * `$TWEET_BASE_DIR/on_command.*` (optional): a callback script providing user-defined commands via DMs.

And, after you start the `watch.sh`, following files and directories will be saved under the base directory automatically:

 * `$TWEET_BASE_DIR/responder.sh`: a script to output one of response message by the given input.
 * `$TWEET_BASE_DIR/logs`: a blank directory to store logs.


## Configurations

### `tweet.client.key`

Put [informations of a generated API key](https://apps.twitter.com/), with the format:

~~~
CONSUMER_KEY=xxxxxxxxxxxxxxxxxxx
CONSUMER_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ACCESS_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
ACCESS_TOKEN_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
~~~


### `personality.txt`

TBD


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

#### Message definition file

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

You'll save such a definition file as `greeting.txt` or others.
Lines beginning with `#` are defines keywords.
Others defines response messages.
If one of keyword matches to the body of the mention, one of following messages (chosen at random) will be postead as a reply.
A definition file including no keyword definition will be simply ignored.

Keywords are treated as extended regular expressions.
Meta characters will have to be escaped.

If the file includes only keyword definitions and there is no response messages like:

~~~
# f(xx|uc)k
# shit
# suck
~~~

then the list will work as an NG list.
When the given message matches to the keywords, the bot will ignore the tweet - never favorited, never replied, never followed.
You'll save such a definition file as `forbidden.txt` or others.

This file must be encoded in UTF-8.


#### Detection order of multiple definition files

Multiple definition files in the `responses` directory will be used with the order: sorted by their name.
For example, if there are both `greeting.txt` and `forbidden.txt`, they are sorted alphabetically as "`forbidden.txt`, `greeting.txt`" and used by the order.
If you hope to change the detection order, add some prefix to control their order like `000_forbidden.txt`, `010_bye.txt`, and others.


#### How to update response messages manually?

If you simply hope to add new response messages to definition files, you can do it freely.
The bot will use newly added messages automatically.

If you add new definition file, remove existing file, or change matching keywords part of any existing file, then you must run the script `generate_responder.sh` manually.
Then the `responder.sh` in the base directory will be regenerated and the running bot will use it automatically.

~~~
$ cd $TWEET_BASE_DIR
$ /path/to/generate_responder.sh
~~~



### `administrators.txt`

TBD.
