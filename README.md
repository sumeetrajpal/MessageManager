# MessageManager

MessageManager is framework for asynchronous bidirectional agent to device communication. 
The library is the successor to [Bullwinkle](https://github.com/electricimp/Bullwinkle).

The library uses [ConnectionManager](https://github.com/electricimp/ConnectionManager) on the device side 
to receive notifications of connection and disconnection events, and to monitor connection status (ie. so that no attempt it made to send messages when the device is disconnected).

**To add this library to your project, add** `#require "messagemanager.class.nut:0.9.1"` **to the top of your agent and device code.**

**Note** MessageManager is designed to run over reliable (ie. TCP/TLS) connections. Retries only occur in the case of dropped connections or lost packets, or if called manually from [beforeSend()](#mmanager_before_send) or [beforeRetry()](#mmanager_before_retry).

## API Overview

- [MessageManager](#mmanager) &mdash; The core library. It is used to add/remove handlers, and to send messages
    - [MessageManager.send()](#mmanager_send) &mdash; Sends the data message
    - [MessageManager.on()](#mmanager_on) &mdash; Sets the callback which will be called when 
    a message with the specified name is received
    - [MessageManager.beforeSend()](#mmanager_before_send) &mdash; Sets the callback which will be called 
    before a message is sent
    - [MessageManager.beforeRetry()](#mmanager_before_retry) &mdash; Sets the callback which will be called 
    before a message is retried
    - [MessageManager.onFail()](#mmanager_on_fail) &mdash; Sets the callback which will be called when an error occurs
    - [MessageManager.onTimeout()](#mmanager_on_timeout) &mdash; Sets the callback which will be called when an message 
    times out
    - [MessageManager.onAck()](#mmanager_on_ack) &mdash; Sets the callback which will be called on the message acknowledgement
    - [MessageManager.onReply()](#mmanager_on_reply) &mdash; Sets the callback which will be called when a sent message receives a reply
    - [MessageManager.getPendingCount](#mmanager_get_pending_count) &mdash; Returns the overall number of pending messages 
    (either waiting for acknowledgement or waiting in the retry queue)
- [MessageManager.DataMessage](#mmanager_data_message) &mdash; The data message object, consisting of the payload 
to be send over the air and meta-information used to control the message lifecycle
    - [MessageManager.DataMessage.onFail()](#mmanager_data_message_on_fail) &mdash; Sets the message-local 
    handler to be called when an error occurs
    - [MessageManager.DataMessage.onTimeout()](#mmanager_data_message_on_timeout) &mdash; Sets the message-local 
    handler to be called when a transmission times out
    - [MessageManager.DataMessage.onAck()](#mmanager_data_message_on_ack) &mdash; Sets the message-local 
    handler to be called when a sent message is acknowledged
    - [MessageManager.DataMessage.onReply()](#mmanager_data_message_on_reply) &mdash; Sets the message-local
    handler to be called when a sent message receives a reply
    
## Details and Usage

### MessageManager

<div id="mmanager"><h4>Constructor: MessageManager(<i>[options]</i>)</h4></div>

Calling the MessageManager constructor creates a new MessageManager instance. An optional 
table can be passed into the constructor (as *options*) to override default behaviours. *options* can contain any of the following keys:

| Key | Data Type | Default Value | Description |
| ----- | -------------- | ------------------ | --------------- |
| *debug* | Boolean | `false` | The flag that enables debug library mode, which turns on extended logging |
| *retryInterval* | Integer | 0 | Changes the default timeout parameter passed to the [retry](#mmanager_retry) method |
| *messageTimeout* | Integer | 10 | Changes the default timeout required before a message is considered failed (to be acknowledged or replied to) |
| *autoRetry* | Boolean | `false` | If set to `true`, MessageManager will automatically continue to retry sending a message until *maxAutoRetries* has been reached when no [onFail()](#mmanager_on_fail) callback is supplied. Please note that if *maxAutoRetries* is set to 0, *autoRetry* will have no limit to the number of times it will retry |
| *maxAutoRetries* | Integer | 0 | Changes the default number of automatic retries to be peformed by the library. After this number is reached the message will be dropped. Please note that the message will automatically be retried if there is when no [onFail()](#mmanager_on_fail) handler registered by the user |
| *connectionManager* | [ConnectionManager](https://github.com/electricimp/ConnectionManager) | `null` | Optional instance of the [ConnectionManager](https://github.com/electricimp/ConnectionManager) library that helps MessageManager to track the connectivity status |
| *nextIdGenerator* | Function | `null` | User-defined callback that generates the next message ID. The function has no parameters |
| *onPartnerConnected* | Function | `null` | Sets the handler to be called when the partner is known to be connected. The handler’s signature is: *handler(reply)*, where *reply(data)* is the callback to respond to the “connected” event |
| *onConnectedReply* | Function | `null` | Sets the handler to be called when the partner responds to the connected status. The handler’s signature is: *handler(response)*, where *response* is the response data |
| *maxMessageRate* | Integer | 10 | Maximum message send rate, which defines the maximum number of messages the library  allows to send per second. If application exceeds the limit, the *onFail* handler is called.<br/>**Note** please don’t change the value unless absolutely necessary. |

##### Examples

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
};

local mm = MessageManager(options);
```

<div id="mmanager_send"><h4>MessageManager.send(<i>name[, data][, handlers][, timeout][, metadata]</i>)</h4></div>

Sends a named message to the partner side and returns the [MessageManager.DataMessage](#mmanager_data_message) object
created. The *data* parameter can be a basic Squirrel type (`1`, `true`, `"A String"`) or more complex data structures 
such as an array or table, but it must be 
[a serializable Squirrel value](https://electricimp.com/docs/resources/serialisablesquirrel/).
        
```squirrel
mm.send("lights", true);   // Turn on the lights
```

*handlers* is a table containing the message-local message event handlers:

| Key | Description | Handler |
| --- | ----------- | ------- |
| *onAck* | Acknowledgement handler | [MessageManager.DataMessage.onAck](#mmanager_data_message_on_ack)  |
| *onFail*| Failure handler | [MessageManager.DataMessage.onFail](#mmanager_data_message_on_fail) |
| *onReply*| Reply handler | [MessageManager.DataMessage.onReply](#mmanager_data_message_on_reply)  |
| *onTimeout*| Timeout handler | [MessageManager.DataMessage.onTimeout](#mmanager_data_message_on_timeout)  |
        
<div id="mmanager_on"><h4>MessageManager.on(<i>messageName, callback</i>)</h4></div>

Sets a message listener function (*callback*) for the specified *messageName*. The callback function takes two parameters: *message* (the message) and *reply* (a function that can be called to reply to the message).

```squirrel
// Get a message, and do something with it
mm.on("lights", function(message, reply) {
    led.write(message.data);
    reply("Got it!");
});
```

<div id="mmanager_before_send"><h4>MessageManager.beforeSend(<i>callback</i>)</h4></div>

Sets the callback which will be called *before* a message is sent. The callback has the following parameters:

| Parameter | Description |
| --- | --- |
| *message* | An instance of [DataMessage](#mmanager_data_message) to be sent |
| *enqueue* | A function with no parameters which appends the message to the retry queue for later processing |
| *drop* | A function which disposes of the message. It takes a single, optional parameter, *silently*, which defaults to `true` and which governs whether the disposal takes place silently or through the *onFail* callbacks |

The *enqueue* and *drop* functions must be called synchronously, if they are called at all.

```squirrel
mm.beforeSend(
    function(msg, enqueue, drop) {
        if (runningOutOfMemory()) {
            drop();
        }
        
        if (needToPreserveMessageOrder() && previousMessagesFailed()) {
            enqueue();
        }
    }
)
```

<div id="mmanager_before_retry"><h4>MessageManager.beforeRetry(<i>callback</i>)</h4></div>

Sets the callback for retry operations. It will be called before the library attempts to re-send the message and has the following parameters:

| Parameter | Description |
| --- | --- |
| *message* | An instance of [DataMessage](#mmanager_data_message) to be re-sent |
| *skip* | A function with a single parameter, *duration*, which postpones the retry attempt and leaves the message in the retry queue for the specified amount of time. If *duration* is not specified, it defaults to the *retryInterval* provided for *MessageManager* [constructor](#mmanager) |
| *drop* | A function which disposes of the message. It takes a single, optional parameter, *silently*, which defaults to `true` and which governs whether the disposal takes place silently or through the *onFail* callbacks |

The *skip* and *drop* functions must be called synchronously, if they are called at all.
 
```squirrel
mm.beforeRetry(
    function(msg, skip, drop) {
        if (runningOutOfMemory()) {
            drop();
        }
        
        if (needToWaitForSomeReasonBeforeRetry()) {
            skip(duration);
        }
    }
)
```

<div id="mmanager_on_fail"><h4>MessageManager.onFail(<i>callback</i>)</h4></div>

Sets the callack to be called when a message error occurs. The callback has the following parameters:

| Parameter | Description |
| --- | --- |
| *message* | An instance of [DataMessage](#mmanager_data_message) that caused the error |
| *reason* | The error description string |
| *retry* | A function that can be invoked to retry sending the message in a specified period of time. This function must be called synchronously, if it is called at all. It takes one parameter, *interval*. If there is no *interval* parameter specified, the *retryInterval* value provided for *MessageManager* [constructor](#mmanager) is used. If the function is not called, the message will expire |

```squirrel
mm.onFail(
    function(msg, error, retry) {
        // Always retry to send the message
        retry();
    }
)
```

<div id="mmanager_on_timeout"><h4>MessageManager.onTimeout(<i>callback</i>)</h4></div>

Sets the callback to be called when a message timeout occurs. The callback has the following parameters:

| Parameter | Description |
| --- | --- |
| *message* | An instance of [DataMessage](#mmanager_data_message) that caused the timeout |
| *wait* | A function which resets the acknowledgement timeout for the message, which means the message will not raise a timeout error for the interval of time specified by the function’s *interval* parameter. This function must be called synchronously |
| *fail* | A function which makes the message fall through the *onFail* callbacks |

If neither *wait* nor *fail* are called, the message will expire.
 
```squirrel
mm.onTimeout(
    function(msg, wait, fail) {
        if (isStillValid(msg)) {
            wait(10);
        } else {
            // Fail otherwise
            fail();
        }
    }
);
```

<div id="mmanager_on_ack"><h4>MessageManager.onAck(<i>callback</i>)</h4></div>

Sets the callback to be called when the message’s receipt is acknowledged. The callback has the following parameters:

| Parameter | Description |
| --- | --- |
| *message* | An instance of [DataMessage](#mmanager_data_message) that was acknowledged |

```squirrel
mm.onAck(
    function(msg) {
        // Just log the ACK event
        server.log("ACK received for " + msg.payload.data);
    }
)
```

<div id="mmanager_on_reply"><h4>MessageManager.onReply(<i>handler</i>)</h4></div>

Sets the callback to be called when the message is replied to. The callback has the following parameters:

| Parameter | Description |
| --- | --- |
| *message* | An instance of [DataMessage](#mmanager_data_message) that was replied to |
| *response* | The response from the partner |

```squirrel
mm.onReply(
    function(msg, response) {
        processResponseFor(msg.payload.data, response);
    }
)
```

<div id="mmanager_get_pending_count"><h4>MessageManager.getPendingCount()</h4></div>

Returns the overall number of pending messages (either waiting for acknowledgement or waiting in the retry queue).

```squirrel
if (mm.getPendingCount() < SOME_MAX_PENDING_COUNT) {
    mm.send("temp", temp);
} else {
    // do something else
}
```

<div id="mmanager_data_message"><h3>MessageManager.DataMessage</h3></div>

MessageManager.DataMessage instances are not intended to be created by users manually &mdash; they are always returned from the [MessageManager.send()](#mmanager_send) method.

<div id="mmanager_data_message_on_fail"><h4>MessageManager.DataMessage.onFail()</h4></div>

Sets a message-local version of the [MessageManager.onFail()](#mmanager_on_fail) handler.

<div id="mmanager_data_message_on_timeout"><h4>MessageManager.DataMessage.onTimeout()</h4></div>

Sets a message-local version of the [MessageManager.onTimeout()](#mmanager_on_timeout) handler.

<div id="mmanager_data_message_on_ack"><h4>MessageManager.DataMessage.onAck()</h4></div>

Sets a message-local version of the [MessageManager.onAck()](#mmanager_on_ack) handler.

<div id="mmanager_data_message_on_reply"><h4>MessageManager.DataMessage.onReply()</h4></div>

Sets a message-local version of the [MessageManager.onReply()](#mmanager_on_reply) handler.

### Other Usage Examples

#### Integration with [ConnectionManager](https://github.com/electricimp/ConnectionManager)

```squirrel
// Device code

#require "ConnectionManager.class.nut:1.0.2"
#require "MessageManager.class.nut:0.9.1"

local cm = ConnectionManager({
    "blinkupBehavior": ConnectionManager.BLINK_ALWAYS,
    "stayConnected": true
});

// Set the recommended buffer size 
// (see https://github.com/electricimp/ConnectionManager for details)
imp.setsendbuffersize(8096);

local config = {
    "messageTimeout": 2,
    "connectionManager": cm
};

local counter = 0;
local mm = MessageManager(config);

mm.onFail(
    function(msg, error, retry) {
        server.log("Error occurred: " + error);
        retry();
    }
);

mm.onReply(
    function(msg, response) {
        server.log("Response for " + msg.payload.data + " received: " + response);
    }
);

function sendData() {
    mm.send("name", counter++);
    imp.wakeup(1, sendData);
}

sendData();
```

```squirrel
// Agent code

#require "MessageManager.class.nut:0.9.1"

local mm = MessageManager();

mm.on("name", function(data, reply) {
    server.log("message received: " + data);
    reply("Got it!");
});
```

## License

MessageManager is licensed under the [MIT License](./LICENSE).
