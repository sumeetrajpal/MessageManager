// Copyright (c) 2016 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// Default configuration values
// TODO: revise the values once again
const MM_DEFAULT_DEBUG                = 0
const MM_DEFAULT_MSG_TIMEOUT          = 5 // sec
const MM_DEFAULT_QUEUE_CHECK_INTERVAL = 0.1 // sec

// Keep it zero for now to make sure messages are being retried on every queue iteration.
const MM_DEFAULT_RETRY_INTERVAL       = 0

// Message types
const MM_MESSAGE_NAME_DATA    = "MM_DATA"
const MM_MESSAGE_NAME_REPLY   = "MM_REPLY"
const MM_MESSAGE_NAME_ACK     = "MM_ACK"
const MM_MESSAGE_NAME_NACK    = "MM_NACK"

// Error messages
// TODO: not sure if we want to define it here though
const MM_ERR_TIMEOUT          = "Message timeout"
const MM_ERR_NO_HANDLER       = "No handler"

class MessageManager {

    static version = [0, 0, 1];

    // Queue of messages that are pending for acknowledgement
    _sentQueue = null

    // Queue of messages that are pending for retry
    _retryQueue = null

    // Current message id
    _nextId = null

    // Handler to be called on a message received 
    _on = null

    // Handler to be called right before a message is sent
    _beforeSend = null

    // Handler to be called before the message is being retried
    _beforeRetry = null

    // The device or agent object
    _partner = null  

    // Timer for checking the queues
    _queueTimer = null

    // Message timeout
    _msgTimeout = null

    // Is debug mode enabled
    _debug = null

    // Message retry interval. We try to sesend message after
    // it sits in the retry queue for this amount of time.
    _retryInterval = null

    // ConnectionManager instance (for device only). 
    // Optional parameter for MessageManager
    _cm = null

    // Data message class definition. Any message being sent by the user
    // is considered to be data message.
    //
    // The class defines the data message structure and handlers.
    _DataMessage = class {
        
        // Message payload to be sent
        payload = null

        // Error handler
        errHandler = null

        // Acknowledgement handler
        ackHandler = null

        // Reply handler
        replyHandler = null

        // Individual message timeout
        timeout = null

        // Message metadata that can be used for application specific purposes
        metadata = null

        // Data message constructor
        // Constructor is not going to be called from the user code
        //
        // Parameters:
        //      id              Data message unique identifier
        //      name            Data message name
        //      data            The actual data being sent
        //      timeout         Individual message timeout
        //
        // Returns:             Data message object created
        function constructor(id, name, data, timeout) {
            payload = {
                "id": id,
                "type": MM_MESSAGE_NAME_DATA,
                "name": name,
                "data": data,
                "sent": null,
                "created": time()
            }
            this.timeout = timeout
            this.metadata = {}
        }

        // Sets the error handler to be called when 
        // an error while sending the message occurs
        //
        // Parameters:
        //      handler         The handler to be called. It has signature:
        //                      handler(message, reason, retry)
        //                      Paremeters:
        //                          message         The message that received an error
        //                          reason          The error reason details
        //                          retry           The function to be called
        //
        // Returns:             Data message object
        function onError(handler) {
            errHandler = handler
            return this
        }

        // Sets the acknowledgement handler to be called
        // when a message is acked by the corresponding party
        //
        // Parameters:
        //      handler         The handler to be called. It has signature:
        //                      handler(message)
        //                      Paremeters:
        //                          message         The message that was acked
        //
        // Returns:             Data message object
        function onAcked(handler) {
            ackHandler = handler
            return this
        }

        // Sets the acknowledgement handler to be called
        // when a message is acked by the corresponding party
        //
        // Parameters:
        //      handler         The handler to be called. It has signature:
        //                      handler(message, response), where
        //                          message         The message that was replied to
        //                          response        Response received as reply
        //
        // Returns:             Data message object
        function onReply(handler) {
            replyHandler = handler
            return this
        }
    }

    // MessageManager constructor
    //
    // Parameters:
    //      config          Configuration of the message manager
    //
    // Returns:             MessageManager object created
    function constructor(config = null, cm = null) {
        if (!config) {
            config = {}
        }
        _cm = cm

        _nextId = 0
        _sentQueue  = {}
        _retryQueue = {}

        // Handlers
        _on = {}

        // Partner initialization
        _partner = _isAgent() ? device : agent;
        _partner.on(MM_MESSAGE_NAME_ACK, _onAck.bindenv(this))
        _partner.on(MM_MESSAGE_NAME_DATA, _onData.bindenv(this))
        _partner.on(MM_MESSAGE_NAME_NACK, _onNack.bindenv(this))
        _partner.on(MM_MESSAGE_NAME_REPLY, _onReply.bindenv(this))

        // Read configuration
        _debug         = "debug"         in config ? config["debug"]         : MM_DEFAULT_DEBUG
        _msgTimeout    = "msgTimeout"    in config ? config["msgTimeout"]    : MM_DEFAULT_MSG_TIMEOUT
        _retryInterval = "retryInterval" in config ? config["retryInterval"] : MM_DEFAULT_RETRY_INTERVAL
    }

    // Sends data message
    //
    // Parameters:
    //      name            Name of the message to be sent
    //      data            Data to be sent
    //      timeout         Individual message timeout
    //
    // Returns:             The data message object created
    function send(name, data, timeout=null) {
        local msg = _DataMessage(_getNextId(), name, data, timeout)
        if (!_isConnected()) {
            _enqueue(msg)
        } else {
            _send(msg)
        }
        return msg
    }

    // Sets the handler which will be called before a message is sent
    //
    // Parameters:
    //      handler         The handler to be called before send. The handler's signature:
    //                          handler(message, enqueue), where
    //                              message         The message to be sent
    //                              enqueue         The function that makes the message
    //                                              appended to the retry queue for
    //                                              later processing
    //                                              enqueue() has no arguments
    //
    // Returns:             Nothing
    function beforeSend(handler) {
        _beforeSend = handler
    }


    // Sets the handler for send operation, which will
    // be called before the message is retried
    //
    // Parameters:
    //      handler         The handler to be called before retry. The handler's signature:
    //                          handler(message, dispose), where
    //                              message         The message that was replied to
    //                              dispose         The function that makes the message
    //                                              permanently removed from the retry queue
    //                                              dispose() has ho arguments
    //
    // Returns:             Nothing
    function beforeRetry(handler) {
        _beforeRetry = handler
    }

    // Sets the handler, which will be called when a message with the specified
    // name is received
    //
    // Parameters:
    //      name            The name of the message to register the handler for
    //      handler         The handler to be called. The handler's signature:
    //                          handler(message, reply), where
    //                              message         The message received
    //                              reply           The function that can be used to reply
    //                                              to the received message:
    //                                              reply(data)
    //
    // Returns:             Nothing
    function on(name, handler) {
        _on[name] <- handler
    }

    // Returns the size of the pending for ack queue
    //
    // Parameters:
    //
    // Returns:             The size of the pending for ack queue
    function getSizeOfWaitingForAck() {
        return _sentQueue.len()
    }

    // Returns the size of the retry queue
    //
    // Parameters:
    //
    // Returns:             The size of the retry queue
    function getSizeOfRetry() {
        return _retryQueue.len()
    }

    // Enqueues the message
    //
    // Parameters:
    //      msg             The message to be queued
    //
    // Returns:             Nothing
    function _enqueue(msg) {
        _log("Adding for retry: " + msg.payload.data)
        _retryQueue[msg.payload["id"]] <- msg
        _startTimer()
    }

    // Returns true if the code is running on the agent side, false otherwise
    //
    // Parameters:    
    //
    // Returns:             true for agent and false for device
    function _isAgent() {
        return imp.environment() == ENVIRONMENT_AGENT
    }   

    // Returns true if the imp and the agent are connected, false otherwise
    //
    // Parameters:    
    //
    // Returns:             true if imp and agent are 
    //                      connected, false otherwise
    function _isConnected() {
        local connected = false
        if (_isAgent()) {
            connected = device.isconnected()
        } else {
            connected = _cm ? _cm.isConnected() : server.isconnected()
        }
        return connected
    }

    // The sent and reply queues processor
    // Handles timeouts, does resent, etc.
    //
    // Parameters:    
    //
    // Returns:             Nothing
    function _checkQueues() {
        // Clean up the timer
        _queueTimer = null

        // Process timed out messages from the sent (waiting for ack) queue
        local curTime = time()
        foreach (id, msg in _sentQueue) {
            local timeout = msg.timeout ? msg.timeout : _msgTimeout
            if (curTime - msg.payload["sent"] > timeout) {
                local onErr = msg.errHandler
                if (_isFunc(onErr)) {
                    onErr(msg, MM_ERR_TIMEOUT, function () {
                        _enqueue(msg)
                    })
                }
                delete _sentQueue[id]
            }
        }

        // There is nothing to do when disconnected
        if (!_isConnected()) {
            return
        }

        // Process retry message queue
        foreach (id, msg in _retryQueue) {
            _retry(msg)
        }
    }

    // The sent and reply queues processor
    // Handles timeouts, retries, etc.
    //
    // Parameters:    
    //
    // Returns:             Nothing
    function _startTimer() {
        if (_queueTimer) {
            // The timer is running already
            return
        }
        _queueTimer = imp.wakeup(MM_DEFAULT_QUEUE_CHECK_INTERVAL, 
                                _checkQueues.bindenv(this))
    }

    // Returns true if the argument is function and false otherwise
    //
    // Parameters:    
    //
    // Returns:             true if the argument is function and false otherwise
    function _isFunc(f) {
        return f && typeof f == "function"
    }

    // Sends the message and restarts the queue timer
    //
    // Parameters:          Message to be sent
    //
    // Returns:             Nothing
    function _sendMessage(msg) {
        _log("Sending: " + msg.payload.data)
        local payload = msg.payload

        local status = _partner.send(MM_MESSAGE_NAME_DATA, payload)

        if (!status) {
            // The message was successfully sent
            // Update the "sent" time
            payload["sent"] <- time()
            _sentQueue[payload["id"]] <- msg
            // Make sure the timer is running
            _startTimer()
        } else {
            // Presumably there is a connectivity issue, 
            // enqueue for further retry
            _enqueue(msg)
        }
    }

    // Retries to send the message, and executes the beforeRerty timer
    //
    // Parameters:          Message to be resent
    //
    // Returns:             Nothing
    function _retry(msg) {
        _log("Retrying to send: " + msg.payload.data)

        local send = true
        local payload = msg.payload

        delete _retryQueue[payload["id"]]

        if (_isFunc(_beforeRetry)) {
            _beforeRetry(msg, function/*dispose*/() {
                // User requests to dispose the message, so drop it on the floor
                send = false
            })
        }

        if (send) {
            _sendMessage(msg)
        }
    }

    // Calls the before send handler and sends the message
    //
    // Parameters:          Message to be resent
    //
    // Returns:             Nothing
    function _send(msg) {
        local send = true
        if (_isFunc(_beforeSend)) {
            _beforeSend(msg, function/*enqueue*/() {
                _enqueue(msg)
                send = false                
            })
        }

        if (send) {
            _sendMessage(msg)
        }
    }

    // A handler for message received (agent/device.on) events
    //
    // Parameters:          Message payload received
    //
    // Returns:             Nothing
    function _onData(payload) {

        // Call the on callback
        local name = payload["name"]
        local data = payload["data"]
        local replied = false
        local handlerFound = false
        local error = 0

        if (name in _on) {
            local handler = _on[name]
            if (_isFunc(handler)) {
                handlerFound = true
                handler(data, function/*reply*/(data = null) {
                    replied = true
                    error = _partner.send(MM_MESSAGE_NAME_REPLY, {
                        "id"   : payload["id"]
                        "data" : data
                    })
                })
            }
        }

        // If message was not replied, send the ACK
        if (!replied) {
            error = _partner.send(MM_MESSAGE_NAME_ACK, {
                "id" : payload["id"]
            })
        }

        // No valid handler - send NACK
        if (!handlerFound) {
            error = _partner.send(MM_MESSAGE_NAME_NACK, {
                "id" : payload["id"]
            })
        }

        if (error) {
            // Responding to a message failed
            // though this is a valid case
            _log("Responding to a message failed")
        }
    }

    // A handler for message acknowledgement
    //
    // Parameters:          Acknowledgement message containing original message id
    //
    // Returns:             Nothing
    function _onAck(payload) {
        local id = payload["id"]
        if (id in _sentQueue) {
            local msg = _sentQueue[id]
            local onAcked = msg.ackHandler

            if (_isFunc(onAcked)) {
                onAcked(msg)
            }

            // Delete the acked message from the queue
            delete _sentQueue[id]
        }
    }

    // A handler for message nack events
    //
    // Parameters:          Payload containing id of the message that failed to be acknowledged
    //
    // Returns:             Nothing
    function _onNack(payload) {
        local id = payload["id"]
        if (id in _sentQueue) {
            local msg = _sentQueue[id]
            local onErr = msg.errHandler

            if (_isFunc(onEr)) {
                onErr(MM_ERR_NO_HANDLER, function () {
                    _enqueue(msg)
                })
            }
        }
    }

    // A handler for message replies
    //
    // Parameters:          Payload containing id and response data for reply
    //
    // Returns:             Nothing
    function _onReply(payload) {
        local id = payload["id"]
        if (id in _sentQueue) {
            local msg = _sentQueue[id]
            local onReply = msg.replyHandler

            if (_isFunc(onReply)) {
                onReply(msg, payload["data"])
            }

            delete _sentQueue[id]
        }
    }

    // Incremental message id generator
    //
    // Parameters:          
    //
    // Returns:             Next message id
    function _getNextId() {
        _nextId = (_nextId + 1) % RAND_MAX
        return _nextId
    }

    // Implements debug logging. Sends the log message 
    // to the console output if "debug" configuration
    // flag is set
    //
    // Parameters:          
    //
    // Returns:             Nothing
    function _log(message) {
        if (_debug) {
            server.log("[MM] " + message)
        }
    }
}
