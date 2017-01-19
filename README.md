# MessageManager Library 0.0.3 (Alpha)

MessageManager is framework for asynchronous bidirectional agent to device communication. 
The library is a successor of [Bullwinkle](https://github.com/electricimp/Bullwinkle).

The work on MessageManager was inspired by complains on the good old 
[Bullwinkle](https://github.com/electricimp/Bullwinkle), which
did not prove itself to be the most optimized library from the footprint standpoint 
(timers, dynamic memory and traffic utilization). 

So we started working on a completely new library to address these concerns which ended up to be
[MessageManager](https://github.com/electricimp/MessageManager).

## Some MessageManager Features

- Optimized system timers utilization
- Optimized traffic used for service messages (replies and acknowledgements)
- Connection awareness (leveraging optional 
[ConnectionManager](https://github.com/electricimp/ConnectionManager) library and checking the  
device/agent.send status)
- Support expendable message metadata, which is not sent over the wire
- Per-message timeouts
- API hooks to manage outgoing messages. This may be used to adjust application-specific 
identifiers or timestamps, introduce additional fields and meta-information or to delay a message delivery
- API hooks to control retry process. This may be used to dispose outdated messages, 
update it's meta-information or delay retry

## API Overview
- [MessageManager](#mmanager) - The core library - used to add/remove handlers, and send messages
    - [MessageManager.send](#mmanager_send) - Sends the data message
    - [MessageManager.on](#mmanager_on) - Sets the callback, which will be called when 
    a message with the specified name is received
    - [MessageManager.beforeSend](#mmanager_before_send) - Sets the callback which will be called 
    before a message is sent
    - [MessageManager.beforeRetry](#mmanager_before_retry) - Sets the callback which will be called 
    before a message is retried
    - [MessageManager.onFail](#mmanager_on_fail) - Sets the handler to be called when an error occurs
    - [MessageManager.onTimeout](#mmanager_on_timeout) - Sets the handler to be called when an message 
    times out
    - [MessageManager.onAck](#mmanager_on_ack) - Sets the handler to be called on the message acknowledgement
    - [MessageManager.onReply](#mmanager_on_reply) - Sets the handler to be called when the message is replied
    - [MessageManager.getPendingCount](#mmanager_get_pending_count) - Returns the overall number of pending messages 
    (either waiting for acknowledgement or hanging in the retry queue)
- [MessageManager.DataMessage](#mmanager_data_message) - the data message object, consisting of the payload 
to be send over the air and meta-information used to control the message life-cycle
    - [MessageManager.DataMessage.onFail](#mmanager_data_message_on_fail) - Sets the message-local 
    handler to be called when an error occurs
    - [MessageManager.DataMessage.onTimeout](#mmanager_data_message_on_timeout) - Sets the message-local 
    handler to be called when an message times out
    - [MessageManager.DataMessage.onAck](#mmanager_data_message_on_ack) - Sets the message-local 
    handler to be called on the message acknowledgement
    - [MessageManager.DataMessage.onReply](#mmanager_data_message_on_reply) - Sets the message-local
    handler to be called when the message is replied
    

### Details and Usage

#### MessageManager

<div id="mmanager"><h5>Constructor: MessageManager(<i>[options]</i>)</h5></div>

Calling the MessageManager constructor creates a new MessageManager instance. An optional *options* 
table can be passed into the constructor to override default behaviours.

<div id="mmanager_options"><h6>options</h6></div>
A table containing any of the following keys may be passed into the MessageManager constructor to modify the default behavior:

| Key | Data Type | Default Value | Description |
| ----- | -------------- | ------------------ | --------------- |
| *debug* | Boolean | `false` | The flag that enables debug library mode, which turns on extended logging. |
| *retryInterval* | Integer | 10 | Changes the default timeout parameter passed to the [retry](#mmanager_retry) method. |
| *messageTimeout* | Integer | 10 | Changes the default timeout required before a message is considered failed (to be acknowledged or replied). |
| *autoRetry* | Boolean | `false` | If set to `true`, MessageManager will automatically continue to retry sending a message until *maxAutoRetries* has been reached when no [onFail](#mmanager_on_fail) handler is supplied. Please note if *maxAutoRetries* is set to 0, *autoRetry* will have no limit to the number of times it will retry. |
| *maxAutoRetries* | Integer | 0 | Changes the default number of automatic retries to be peformed by the library. After this number is reached the message will be dropped. Please not the message will automatically be retried if there is when no [onFail](#mmanager_on_fail) handler registered by the user. |
| *connectionManager* | [ConnectionManager](https://github.com/electricimp/ConnectionManager) | `null` | Optional instance of [ConnectionManager](https://github.com/electricimp/ConnectionManager) library that helps MessageManager to track the connectivity status. |

###### Examples

```squirrel
// Initialize using default settings
local mm = MessageManager();
```

```squirrel
// Create ConnectionManager instance
local cm = ConnectionManager({
    "blinkupBehavior": ConnectionManager.BLINK_ALWAYS,
    "stayConnected": true
});
imp.setsendbuffersize(8096);

// MessageManager options
local options = {
    "debug": true,
    "retryInterval": 15,
    "messageTimeout": 2,
    "autoRetry": true,
    "maxAutoRetries": 10,
    "connectionManager": cm
}

local mm = MessageManager(options);
```

<div id="mmanager_send"><h5>MessageManager.send(name, [data, handlers, timeout, metadata])</h5></div>

Sends a named message to the partner side and returns the [MessageManager.DataMessage](#mmanager_data_message) object
created.

<div id="mmanager_on"><h5>MessageManager.on</h5></div>
<div id="mmanager_before_send"><h5>MessageManager.beforeSend</h5></div>
<div id="mmanager_before_retry"><h5>MessageManager.beforeRetry</h5></div>
<div id="mmanager_on_fail"><h5>MessageManager.onFail</h5></div>
<div id="mmanager_on_timeout"><h5>MessageManager.onTimeout</h5></div>
<div id="mmanager_on_ack"><h5>MessageManager.onAck</h5></div>
<div id="mmanager_on_reply"><h5>MessageManager.onReply</h5></div>
<div id="mmanager_get_pending_count"><h5>MessageManager.getPendingCount</h5></div>

<div id="mmanager_data_message"><h4>MessageManager.DataMessage</h4></div>

A `MessageManager.DataMessage` instances are not supposed to be created by users manually and are always returned from
the [MessageManager.send](#mmanager_send) method.

<div id="mmanager_data_message_on_fail"><h5>MessageManager.DataMessage.onFail</h5></div>
<div id="mmanager_data_message_on_timeout"><h5>MessageManager.DataMessage.onTimeout</h5></div>
<div id="mmanager_data_message_on_ack"><h5>MessageManager.DataMessage.onAck</h5></div>
<div id="mmanager_data_message_on_reply"><h5>MessageManager.DataMessage.onReply</h5></div>

### Other Usage Examples

#### Integration with [ConnectionManager](https://github.com/electricimp/ConnectionManager)

```squirrel
// Device code

#require "ConnectionManager.class.nut:1.0.2"
#require "MessageManager.class.nut:0.0.2"

local cm = ConnectionManager({
    "blinkupBehavior": ConnectionManager.BLINK_ALWAYS,
    "stayConnected": true
})

// Set the recommended buffer size 
// (see https://github.com/electricimp/ConnectionManager for details)
imp.setsendbuffersize(8096)

local config = {
    "msgTimeout": 2
}

local counter = 0
local mm = MessageManager(config, cm)

mm.onFail(
    function(msg, error, retry) {
        server.log("Error occurred: " + error)
        retry()
    }
)

mm.onReply(
    function(msg, response) {
        server.log("Response for " + msg.payload.data + " received: " + response)
    }
)

function sendData() {
    mm.send("name", counter++);
    imp.wakeup(1, sendData)
}

sendData()
```

```squirrel
// Agent code

#require "MessageManager.class.nut:0.0.2"

local mm = MessageManager()

mm.on("name", function(data, reply) {
    server.log("message received: " + data)
    reply("Got it!")
})
```

## License

Bullwinkle is licensed under the [MIT License](./LICENSE).
