# MessageManager Library 0.0.4 (Alpha)

MessageManager is framework for asynchronous bidirectional agent to device communication. 
The library is a successor of [Bullwinkle](https://github.com/electricimp/Bullwinkle).

**Please note:** the MessageManager is designed to run over reliable (i.e. TCP/TLS) connections. Retries only occur in the case
of dropped connections or lost packets.

The library uses [ConnectionManager](https://github.com/electricimp/ConnectionManager) on the device side 
to get notified of the connected/disconnected events and also to get a better way to find out the actual 
connection status (i.e. we are not trying to send messages when disconnected).

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
| *retryInterval* | Integer | 0 | Changes the default timeout parameter passed to the [retry](#mmanager_retry) function. |
| *messageTimeout* | Integer | 10 | Changes the default timeout required before a message is considered failed (to be acknowledged or replied). |
| *autoRetry* | Boolean | `false` | If set to `true`, MessageManager will automatically continue to retry sending a message until *maxAutoRetries* has been reached when no [onFail](#mmanager_on_fail) handler is supplied. Please note if *maxAutoRetries* is set to 0, *autoRetry* will have no limit to the number of times it will retry. |
| *maxAutoRetries* | Integer | 0 | Changes the default number of automatic retries to be peformed by the library. After this number is reached the message will be dropped. Please not the message will automatically be retried if there is when no [onFail](#mmanager_on_fail) handler registered by the user. |
| *connectionManager* | [ConnectionManager](https://github.com/electricimp/ConnectionManager) | `null` | Optional instance of [ConnectionManager](https://github.com/electricimp/ConnectionManager) library that helps MessageManager to track the connectivity status. |
| *nextIdGenerator* | Function | `null` | User-defined callback that generates the next message id. The function has no parameters. |

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
};

local mm = MessageManager(options);
```

<div id="mmanager_send"><h5>MessageManager.send(<i>name, [data, handlers, timeout, metadata]</i>)</h5></div>

Sends a named message to the partner side and returns the [MessageManager.DataMessage](#mmanager_data_message) object
created.The *data* parameter can be a basic Squirrel type (`1`, `true`, `"A String"`) or more complex data structures 
such as an array or table, but it must be 
[a serializable Squirrel value](https://electricimp.com/docs/resources/serialisablesquirrel/).
        
```squirrel
mm.send("lights", true);   // Turn on the lights
```

*handlers* is a table containing the message-local message event handlers:

| Key | Description | Handler |
| ----- | -------------- | ------------------ |
| *onAck* | Acknowledgement handler | [MessageManager.DataMessage.onAck](#mmanager_data_message_on_ack)  |
| *onFail*| Failure handler | [MessageManager.DataMessage.onFail](#mmanager_data_message_on_fail) |
| *onReply*| Reply handler | [MessageManager.DataMessage.onReply](#mmanager_data_message_on_reply)  |
| *onTimeout*| Timeout handler | [MessageManager.DataMessage.onTimeout](#mmanager_data_message_on_timeout)  |
        
The *send()* method returns a [MessageManager.DataMessage](#mmanager_data_message) object.

<div id="mmanager_on"><h5>MessageManager.on(<i>messageName, callback</i>)</h5></div>


Sets a message listener (the *callback*) for the specified *messageName*. 
The callback function takes two parameters: *message* (the message) and *reply* (a function that can be called to 
reply to the message).

```squirrel
// Get a message, and do something with it
mm.on("lights", function(message, reply) {
    led.write(message.data);
    reply("Got it!");
});
```

<div id="mmanager_before_send"><h5>MessageManager.beforeSend(<i>handler</i>)</h5></div>

Sets the handler which will be called before a message is sent. The handler has the following signature:

``handler(message, enqueue, drop)``

where *message* is an instance of [DataMessage](#mmanager_data_message) to be sent, 
*enqueue()* is the callback with no parameters which when called makes the 
message appended to the retry queue for later processing, *drop(silently=true)* is the callback which when called
disposes the message (either silently or through the *onFail* callbacks).

The *enqueue* and *drop* functions must be called synchronously if they are to be called at all.

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

*drop()* has *silently* parameter which if set to *false* makes the [MessageManager.onFail](#mmanager_on_fail) and
[MessageManager.DataMessage.onFail](#mmanager_data_message_on_fail) handlers to be called if any of those are registered. 
Otherwise, if *silently* is not specified or is set to *true*, calling *drop()* results in a silent message disposal.

<div id="mmanager_before_retry"><h5>MessageManager.beforeRetry(<i>handler</i>)</h5></div>

Sets the handler for retry operation, which will be called before the message is retried. The handler has the following 
signature:

``handler(message, skip, drop)``

where *message* is an instance of [DataMessage](#mmanager_data_message) to be retried, 
*skip(duration)* is callback which when called postpones the retry
attempt and leaves the message in the retry queue for the specified amount of time, *drop(silently=true)* is 
the callback which when called disposes the message (either silently or through the *onFail* callback).

The *skip* and *drop* functions must be called synchronously if they are to be called at all.
 
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

The *duration* parameter of *skip(duration)* if not specified defaults to *retryInterval* provided for 
*MessageManager* [constructor](#mmanager).

*drop()* has a *silently* parameter which if set to *false* makes the [MessageManager.onFail](#mmanager_on_fail) and
[MessageManager.DataMessage.onFail](#mmanager_data_message_on_fail) handlers to be called if any of those are registered. 
Otherwise, if silently is not specified or is set to true, calling to *drop()* results in a silent message disposal.

<div id="mmanager_on_fail"><h5>MessageManager.onFail(<i>handler</i>)</h5></div>

Sets the handler to be called when an error with a message occurs. The handler has the signature
 
``handler(message, error, retry)``

where *message* is an instance of [DataMessage](#mmanager_data_message) that caused the error, 
*reason* is the error description string. The *retry* parameter is a 
function that can be invoked to retry sending the message in a specified period of time. This function must be called 
synchronously if it is to be called at all. If the *retry(interval)* function is not called the message will be expired.

If there is no *interval* parameter specified for the *retry* function, the *retryInterval* value provided for 
*MessageManager* [constructor](#mmanager) is used.

```squirrel
mm.onFail(
    function(msg, error, retry) {
        // Always retry to send the message
        retry();
    }
)
```

<div id="mmanager_on_timeout"><h5>MessageManager.onTimeout(<i>handler</i>)</h5></div>

Sets the handler to be called when message timeout error occurs. The *handler* callback has the following signature:

``handler(message, wait, fail)``

where *message* is an instance of [DataMessage](#mmanager_data_message) that caused the timeout error, 
and *wait(interval)* is the handler, which when is called,
resets the acknowledgement timeout for the message, which means the message will not raise a timeout error for the 
next specified interval of time. This function must be called synchronously if it is to be called at all.
 
The *fail* parameter is a callback function which when called makes the message to fall through the *onFail* callbacks.

If none of *wait* or *fail* callbacks are called, the message will be expired.
 
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

<div id="mmanager_on_ack"><h5>MessageManager.onAck(<i>handler</i>)</h5></div>

Sets the handler to be called on the message acknowledgement. The handler has the signature
``handler(message)``

where *message* is an instance of [DataMessage](#mmanager_data_message) that was acknowledged by the partner.

```squirrel
mm.onAck(
    function(msg) {
        // Just log the ACK event
        server.log("ACK received for " + msg.payload.data);
    }
)
```

<div id="mmanager_on_reply"><h5>MessageManager.onReply(<i>handler</i>)</h5></div>

Sets the handler to be called when the message is replied. The handler has the signature

``handler(message, response)``

where *message* is an instance of [DataMessage](#mmanager_data_message) that was replied to and *response* is the 
partner response body.
 
```squirrel
mm.onReply(
    function(msg, response) {
        processResponseFor(msg.payload.data, response);
    }
)
```

<div id="mmanager_get_pending_count"><h5>MessageManager.getPendingCount()</h5></div>

Returns the overall number of pending messages (either waiting for acknowledgement or hanging in the retry queue).

```squirrel
if (mm.getPendingCount() < SOME_MAX_PENDING_COUNT) {
    mm.send("temp", temp);
} else {
    // do something else
}
```

<div id="mmanager_data_message"><h4>MessageManager.DataMessage</h4></div>

A `MessageManager.DataMessage` instances are not supposed to be created by users manually and are always returned from
the [MessageManager.send](#mmanager_send) function.

<div id="mmanager_data_message_on_fail"><h5>MessageManager.DataMessage.onFail</h5></div>

Message-local version of the [MessageManager.onFail](#mmanager_on_fail) handler.

<div id="mmanager_data_message_on_timeout"><h5>MessageManager.DataMessage.onTimeout</h5></div>

Message-local version of the [MessageManager.onTimeout](#mmanager_on_timeout) handler.

<div id="mmanager_data_message_on_ack"><h5>MessageManager.DataMessage.onAck</h5></div>

Message-local version of the [MessageManager.onAck](#mmanager_on_ack) handler.

<div id="mmanager_data_message_on_reply"><h5>MessageManager.DataMessage.onReply</h5></div>

Message-local version of the [MessageManager.onReply](#mmanager_on_reply) handler.

### Other Usage Examples

#### Integration with [ConnectionManager](https://github.com/electricimp/ConnectionManager)

```squirrel
// Device code

#require "ConnectionManager.class.nut:1.0.2"
#require "MessageManager.class.nut:0.0.2"

local cm = ConnectionManager({
    "blinkupBehavior": ConnectionManager.BLINK_ALWAYS,
    "stayConnected": true
});

// Set the recommended buffer size 
// (see https://github.com/electricimp/ConnectionManager for details)
imp.setsendbuffersize(8096)

local config = {
    "messageTimeout": 2,
    "connectionManager": cm
};

local counter = 0
local mm = MessageManager(config)

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

#require "MessageManager.class.nut:0.0.2"

local mm = MessageManager();

mm.on("name", function(data, reply) {
    server.log("message received: " + data);
    reply("Got it!");
});
```

## License

Bullwinkle is licensed under the [MIT License](./LICENSE).
