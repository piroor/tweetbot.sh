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
   * retweet it with comments, based on supplied response messages.
   * respond to it, if it is a mention to you and you supplied response messages.
 * If someone posted tweets including keywords you specified, this will...
   * favorite it.
   * retweet it.
   * retweet it with comments, based on supplied response messages.

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
   The process must be restarted if you modify this file.
 * `$TWEET_BASE_DIR/responses` (optional): a directory to put response messages.
 * `$TWEET_BASE_DIR/monologues` (optional): a directory to put monologue messages.

If you permit accessing to direct messages for the app, you'll prepare following files also:

 * `$TWEET_BASE_DIR/on_response_modified.*` (optional): a callback script to be executed when any response message is changed dynamically.
 * `$TWEET_BASE_DIR/on_monologue_modified.*` (optional): a callback script to be executed when any monologue message is changed dynamically.
 * `$TWEET_BASE_DIR/on_command.*` (optional): a callback script providing user-defined commands via DMs.

And, after you start the `watch.sh`, following files and directories will be saved under the base directory automatically:

 * `$TWEET_BASE_DIR/responder.sh`: a script to output one of response message by the given input.
 * `$TWEET_BASE_DIR/monologue_selector.sh`: a script to output one of monologue message by the given time (or the current time).
 * `$TWEET_BASE_DIR/logs`: a directory to store logs.
 * `$TWEET_BASE_DIR/.status`: a directory to store caches and status files.


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

This file defines behaviors of the bot.
The default configurations are:

~~~
WATCH_KEYWORDS=''

FOLLOW_ON_FOLLOWED=true
FOLLOW_ON_MENTIONED=true
FOLLOW_ON_QUOTED=true
FOLLOW_ON_RETWEETED=false

SPAM_USER_PATTERN='follow *(back|me)'

FAVORITE_MENTIONS=true
FAVORITE_QUOTATIONS=true
FAVORITE_SEARCH_RESULTS=true

RETWEET_MENTIONS=false
RETWEET_QUOTATIONS=true
RETWEET_SEARCH_RESULTS=true

RESPOND_TO_MENTIONS=true
RESPOND_TO_QUOTATIONS=true
RESPOND_TO_SEARCH_RESULTS=true

FREQUENCY_OF_CAPRICES=66
NEW_TOPIC=66
CONVERSATION_PERSISTENCE=40

MONOLOGUE_INTERVAL_MINUTES=60
MONOLOGUE_TIME_SPAN="morning/06:00-07:00 \
                     noon/12:00-13:00 \
                     afternoon/15:00-15:30 \
                     evening/17:30-18:30 \
                     night/19:00-21:00 \
                     midnight/23:00-24:00,00:00-03:00"

ADMINISTRATORS=''
~~~

This file must be encoded in UTF-8.

#### Observing of the timeline and search results

`WATCH_KEYWORDS` defines keywords to be watched with the format:

~~~
WATCH_KEYWORDS='Bash, ShellScript, Twitter'
~~~

It is a string of a comma-separated list.
Keywords are treated like conditions with the `OR` logical operator.
Any tweet matched to one of given terms will be detected and treated as "mention" (including "reply"), "quotation", "retweet", or "search result".

#### Auto follow

These parameters define the strategy to follow other users.
By these configurations, this bot will follow the follower back or follow the author of detedted tweets (mentions, quotations, or RTs).

~~~
FOLLOW_ON_FOLLOWED=true
FOLLOW_ON_MENTIONED=true
FOLLOW_ON_QUOTED=true
FOLLOW_ON_RETWEETED=false
~~~

And, you can define blacklist filter to ignore spam accounts.
The pattern is evaluated as an extended regular expression.

~~~
SPAM_USER_PATTERN='follow *(back|me)'
~~~

#### Auto favorite

These parameters define the strategy to favorite tweets by other users.
By these configurations, this bot will favorite detected tweets (mentions, quotations, or search results).

~~~
FAVORITE_MENTIONS=true
FAVORITE_QUOTATIONS=true
FAVORITE_SEARCH_RESULTS=true
~~~

#### Auto retweet

These parameters define the strategy to retweet tweets by other users.
By these configurations, this bot will retweet detected tweets (mentions, quotations, or search results).

~~~
RETWEET_MENTIONS=false
RETWEET_QUOTATIONS=true
RETWEET_SEARCH_RESULTS=true
~~~

#### Auto response and quotation

These parameters define the strategy to reply for tweets by other users.

~~~
RESPOND_TO_MENTIONS=true
RESPOND_TO_QUOTATIONS=true
RESPOND_TO_SEARCH_RESULTS=true
~~~

For mentions, this bot always respond to it as a reply.
Otherwise, if the tweet is not a mention (including `@username` for your account), this bot will post an independent tweet including the URL of the detected tweet - in other words, retweet it with a comment.

#### Tendency of the chatterbot featrue

If someone mentions to the bot, it will replies to the mention always.
However, the length of a conversation is undetermined and the bot continues to talk with any luck.

~~~
FREQUENCY_OF_CAPRICES=66
~~~

The parameter `FREQUENCY_OF_CAPRICES` defines how often become tired on the current topic, between `0` (never tired forever) and `100` (tired just with a response).
If the parameter has a large value, the bot seems to be restless.

~~~
NEW_TOPIC=66
~~~

The parameter `NEW_TOPIC` defines how often start new topic after tired, between `0` (never start new topic) and `100` (always start new topic).
If the parameter has a large value, the bot seems to have much curiosity.

~~~
CONVERSATION_PERSISTENCE=40
~~~

The parameter `CONVERSATION_PERSISTENCE` defines how often continue the current topic without tired, between `0` (never continue to talk) and `100` (continue to talk forever).
If the parameter has a large value, the bot seems to be inquisitive.

#### Monologue tweets

This bot can post monologue tweets with intervals without any cronjob.
The timer counts up from `00:00` and the bot tries to post a monologue for every N minutes specified by the parameter `MONOLOGUE_INTERVAL_MINUTES` (minimum interval = 10 minutes).

~~~
MONOLOGUE_INTERVAL_MINUTES=60
~~~

However, the actual timing of the monologue tweet has a margin.
The shorter one of "10 minutes" or "the 1/3 of the interval" is the margin, and this bot will post a monologue based on calculated probabilities.
For example, if you specify the interval as `60`, then the probabilities of the timing when the monologue will be actually posted is:

 * ...
 * 00:53 0%
 * 00:54 0%
 * 00:55 10% - the beginning of the period
 * 00:56 26%
 * 00:57 42%
 * 00:58 58%
 * 00:59 74%
 * 01:00 90% - the peak (60 minutes from 00:00)
 * 01:01 74%
 * 01:02 58%
 * 01:03 42%
 * 01:04 26%
 * 01:05 10% - the end of the period
 * 01:06 0%
 * 01:07 0%
 * ...

Monologue messages are loaded from definition files, and you can define some special time span with the `MONOLOGUE_TIME_SPAN` parameter.

~~~
MONOLOGUE_TIME_SPAN="morning/06:00-07:00 \
                     noon/12:00-13:00 \
                     afternoon/15:00-15:30 \
                     evening/17:30-18:30 \
                     night/19:00-21:00 \
                     midnight/23:00-24:00,00:00-03:00"
~~~

It is space-separated list of time span definitions with the format: `(name-of-the-span)/(beginning-1)-(end-1),(beginning-2)-(end-2),...,(beginning-N)-(end-N)`
You can define special monologue messages for each special time span.

#### Administrators of the bot

The parameter `ADMINISTRATORS` defines a comma-separated list of administrators who permitted to control the bot via DMs.

~~~
ADMINISTRATORS='your_account, your_project_partner'
~~~

For more details, see following sections.


## Definition of response messages

### Typical file placements

 * responses
   * 000-blocklist.txt
   * 001-good-morning.txt
   * 002-good-afternoon.txt
   * 003-good-evening.txt
   * 004-thanks.txt
   * ...
   * _topics.txt
   * _pong.txt
   * _developments.txt

All files in the `responses` directory are response message definition files.
They have same format described below.

### Basic format of response message definition files

A definition file has two sections: keywords and messages.
Lines starting with `#` define keywords.
Others define messages.
Typical contents of a definition file are here:

(002-good-afternoon.txt)

~~~
# hello
# hi|hey
# good afternoon
# yo

Hi!
Hello!
Aloha!
Ola!
~~~

A keyword can be an extended regular expression.
A definition file with no keyword definition line will be simply ignored.

When the bot detects a mention or reply from another user, it finds a definition file which has a keyword definition matches to the body of the tweet.
Then, one of defined messages are posted as a reply for the mention.

This file must be encoded in UTF-8.

### Block list

A definition file with no message definition line will become a "block list".
For example:

(000-blocklist.txt)

~~~
# f(xx|uc)k
# shit
# suck
~~~

If the body of a mention matches one of keywords in blokc lists, then the bot never follow, favorite, retweet, and replies to the mention.

#### Detection order of multiple definition files

The bot scans all definition files with the order sorted by their filename.
You must put block list files before other regular definition files.
For example, `000-blocklist` and `100-greeting.txt`.

#### Special definition files

For a mention which is not matched to any keyword, this bot generates a random message from sources.
These special definition files are used to generate those default responses:

 * _topics.txt
   * "How are you?"
   * "What's up?"
   * "Hi, what's goin'on?"
   * "How about the new version of this software?"
 * _pong.txt
   * "Oh!"
   * "Wow!"
   * "Hmm...!"
 * _developments.txt
   * "That's true."
   * "That's cool."
   * "You're right."
   * "Exactly!"

#### What you must do when you modify response definition files

`watch.sh` scans all existing definition files on its startup, however, new keywords and definition files added after the `watch.sh` is started won't be loaded.
If you modify keyword definitions while the bot is running, you have to regenerate `responder.sh` manually, by running the script `generate_responder.sh` as:

~~~
$ cd $TWEET_BASE_DIR
$ /path/to/tweetbot.sh/generate_responder.sh
~~~

or

~~~
$ env TWEET_BASE_DIR=/path/to/data/directory /path/to/tweetbot.sh/generate_responder.sh
~~~


## Definition of monologue messages

### Typical file placements

 * monologues
   * morning.txt
   * afternoon.txt
   * all-greeting.txt
   * all-advertisement.txt
   * all-newyear.txt
   * ...

All files in the `monologues` directory are monologue message definition files.
They have same format described below.

### Basic format of monologue message definition files

A definition file contains messages.
All lines define messages.
Typical contents of a definition file are here:

(all-greeting.txt)

~~~
# comment

Hi! I'm a chatterbot. Please talk with me!
Yeah! I'm a chatterbot. Please talk with me!
Did you know? I'm a chatterbot!
~~~

All comment lines starting with `#` are ignored.

This file must be encoded in UTF-8.

#### Directive to specify range of dates

You can specify activation dates for each definition file, like:

~~~
# date: 2016.01.01-2016.01.10

Happy new year!
Hi, happy new year!
~~~

Wildcard is also available. For example:

 * `# date: *.01.01-*.01.10` will be useful for messages like "happy new year" for every year.
 * `# date: *.*.01-*.*.03` will be useful for messages like "hey, don't forget to do the monthly task!" for every month.

#### Detection order of multiple definition files

The bot will choose one of messages from all files which have same prefix like `all`.
There is no order.

#### What you must do when you modify monologue definition files

`watch.sh` scans all existing definition files on its startup, however, new messages and definition files added after the `watch.sh` is started won't be loaded.
If you modify definitions while the bot is running, you have to regenerate `monologue_selector.sh` manually, by running the script `generate_monologue_selector.sh` as:

~~~
$ cd $TWEET_BASE_DIR
$ /path/to/tweetbot.sh/generate_monologue_selector.sh
~~~

or

~~~
$ env TWEET_BASE_DIR=/path/to/data/directory /path/to/tweetbot.sh/generate_monologue_selector.sh
~~~


## Administration via DMs

If your screen name is listed in the `ADMINISTRATORS`, you can control the bot via DMs dynamically.
You simply have to send DMs like following:

 * `+res greeting Good morning!`
 * `post @friend Thank you!`

### Built-in commands

 * `echo`: returns an echo of the given message.
 * `test`: returns a response for the given message.
 * `+res` / `-res`: adds/removes keyword and message definitions for responses.
 * `+(name of a time span group)` / `-(name of a time span group)`: adds/removes message definitions for monologue.
 * `tweet` / `post`: posts the given message as a regular tweet of the bot.
 * `reply`: posts the given message as a reply by the bot.
 * `del` / `delete` / `rem` / `remove`: removes the specified tweet of the bot.
 * `rt` / `retweet`: retweets the given tweet by the bot.
 * `search-result`: treats the given tweet as a search result.
 * `run`: executes user defined commands.

#### `echo`: returns an echo of the given message.

 * Parameters
   * All arguments: the message.
 * Example
   * `echo Hello`
   * `echo OK?`

Simply returns the given message (except the command name `echo`).

#### `test`: returns a response for the given message.

 * Parameters
   * All arguments: the message.
 * Example
   * `echo Hello`
   * `echo OK?`

Treats the given message as a fake mention and returns actual response message.

#### `+res`: adds keyword and message definitions for responses.

 * Parameters
   * 1st argument: a matching keyword.
   * 2nd argument: a valiation of the keyword. (optional)
   * Rest arguments: a response message. (optional)
 * Example
   * `+res Hello > Ola Hi! I'm fine!`
     * keyword: `Hello`
     * valiation: `Ola`
     * response message: `Hi! I'm fine!`
   * `+res Hello > Ola`
     * keyword: `Hello`
     * valiation: `Ola`
     * response message: nothing
   * `+res Hello Hi! I'm fine!`
     * keyword: `Hello`
     * valiation: nothing
     * response message: `Hi! I'm fine!`

This command registers new keyword, valiation of the keyword, and a response message.
Both valiation and message are optional.

#### `-res`: removes keyword and message definitions for responses.

 * Parameters
   * 1st argument: a matching keyword.
   * 2nd argument: a valiation of the keyword. (optional)
   * Rest arguments: a response message. (optional)
 * Example
   * `-res Hello > Ola Hi! I'm fine!`
     * keyword: `Hello`
     * valiation: `Ola`
     * response message: `Hi! I'm fine!`
   * `-res Hello > Ola`
     * keyword: `Hello`
     * valiation: `Ola`
     * response message: nothing
   * `-res Hello Hi! I'm fine!`
     * keyword: `Hello`
     * valiation: nothing
     * response message: `Hi! I'm fine!`

This command unregisters an existing keyword, valiation of the keyword, and a response message.
Both valiation and message are optional.

#### `+(name of a time span group)`: adds message definitions for monologue.

 * Parameters
   * 1st argument: the name of the time span.
   * 2nd argument: an alias of the time span. (optional)
   * Rest arguments: a monologue message. (optional)
 * Example
   * `+all > everytime Did you know? I'm a chatterbot!`
     * group: `all`
     * alias: `everytime`
     * monologue: `Did you know? I'm a chatterbot!`
   * `+all > everytime`
     * group: `all`
     * alias: `everytime`
     * monologue: nothing
   * `+morning Good morning!`
     * group: `morning`
     * alias: nothing
     * monologue: `Good morning!`

This command registers new monologue and alias of the time span group.
Both alias and message are optional.

#### `-(name of a time span group)`: removes message definitions for monologue.

 * Parameters
   * 1st argument: the name of the time span.
   * 2nd argument: an alias of the time span. (optional)
   * Rest arguments: a monologue message. (optional)
 * Example
   * `-all > everytime Did you know? I'm a chatterbot!`
     * group: `all`
     * alias: `everytime`
     * monologue: `Did you know? I'm a chatterbot!`
   * `-all > everytime`
     * group: `all`
     * alias: `everytime`
     * monologue: nothing
   * `-morning Good morning!`
     * group: `morning`
     * alias: nothing
     * monologue: `Good morning!`

This command unregisters an existing monologue and alias of the time span group.
Both alias and message are optional.

#### `tweet` / `post`: posts the given message as a regular tweet of the bot.

 * Parameters
   * All arguments: the messge to be postead as a tweet.
 * Example
   * `tweet Thank you, my friends!`

#### `reply`: posts the given message as a reply by the bot.

 * Parameters
   * 1st argument: the ID of the tweet to be replied.
   * All rest arguments: the messge to be postead as a areply.
 * Example
   * `reply 0123456 @friend Sorry, that's a bug of this chatterbot...`

#### `del` / `delete` / `rem` / `remove`: removes the specified tweet of the bot.

 * Parameters
   * 1st argument: the ID of the tweet to be deleted.
 * Example
   * `del 0123456`

#### `rt` / `retweet`: retweets the given tweet by the bot.

 * Parameters
   * 1st argument: the ID of the tweet to be retweeted.
 * Example
   * `rt 0123456`

#### `search-result`: treats the given tweet as a search result.

 * Parameters
   * 1st argument: the ID of the tweet to be processed as a new search result.
 * Example
   * `search-result 0123456`

When you realized that there is a tweet which should be tracked as a search result but actually not processed, you'll hope to add new response keywords and the existing tweet is processed as a new search result.
This command just does it.
Note that the feature possibly process the tweet multiple times.

#### `run`: executes user defined commands.

 * Parameters
   * All arguments: arguments for user defined commands.
 * Example
   * `run list`
   * `run update`

### User defined DM commands

If there is any executable file named with the prefix `on_command` (like `on_command.sh`, `on_command.rb`, etc.), it is kicked by the DM command `run` with two arguments: the screen name of the sender, and the message body.

This is a sample script to implement `run list` command to return all file names in the `responses` directory:

~~~
#!/usr/bin/env bash

sender="$1"
command="$2"

tweet_sh='tweetbot.sh/tweet.sh/tweet.sh'

list_responses() {
  list="$(cd responses &&
            ls * |
            sort |
            sed 's/.txt$//' |
            paste -s -d ',')"
  echo "list: $list"
  "$tweet_sh" dm $sender "$list" > /dev/null
}

case "$command" in
  list* )
    list_responses
    ;;
esac
~~~


### Callback script for DM commands to modify response message definitions

If there is any executable file named with the prefix `on_response_modified` (like `on_response_modified.sh`, `on_response_modified.rb`, etc.), it is kicked by DM commands `+res` and `-res`.
For example, this is a sample script to do following:

 * Renames newly added definition file with a prefix `300_`.
 * Commits and pushes changes to the Git repository.

~~~
#!/usr/bin/env bash

find responses -name "autoadd_*" | while read path
do
  mv "$path" "$(echo "$path" | sed 's/autoadd_/300_/')"
done

git add responses
git commit -m "Add new response"
git push
~~~

### Callback script for DM commands to modify monologue message definitions

If there is any executable file named with the prefix `on_monologue_modified` (like `on_monologue_modified.sh`, `on_monologue_modified.rb`, etc.), it is kicked by DM commands `+(tine span)` and `-(tine span)`.
For example, this is a sample script to do following:

 * Commits and pushes changes to the Git repository.

~~~
#!/usr/bin/env bash

git add scheduled
git commit -m "Add new monologue"
git push
~~~
