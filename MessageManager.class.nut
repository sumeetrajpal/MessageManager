// Copyright (c) 2016-2017 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// Default configuration values
const MM_DEFAULT_DEBUG                  = 0
const MM_DEFAULT_QUEUE_CHECK_INTERVAL   = 0.5 // sec
const MM_DEFAULT_MSG_TIMEOUT            = 10  // sec
const MM_DEFAULT_RETRY_INTERVAL         = 10  // sec
const MM_DEFAULT_AUTO_RETRY             = 0
const MM_DEFAULT_MAX_AUTO_RETRIES       = 0

// Message types
const MM_MESSAGE_NAME_DATA    = "MM_DATA"
const MM_MESSAGE_NAME_REPLY   = "MM_REPLY"
const MM_MESSAGE_NAME_ACK     = "MM_ACK"
const MM_MESSAGE_NAME_NACK    = "MM_NACK"

// Error messages
const MM_ERR_TIMEOUT          = "Message timeout error"
const MM_ERR_NO_HANDLER       = "No handler error"
const MM_ERR_NO_CONNECTION    = "No connection error"

class MessageManager {

    static version = [0, 0, 2];

    // Queue of messages that are pending for acknowledgement
    _sentQueue = null

    // Queue of messages that are pending for retry
    _retryQueue = null

    // Current message id
    _nextId = null

    // The device or agent object
    _partner = null  

    // Timer for checking the queues
    _queueTimer = null

    // Message timeout
    _msgTimeout = null

    // The flag indicating that the debug mode enabled
    _debug = null

    // ConnectionManager instance (for device only). 
    // Optional parameter for MessageManager
    _cm = null

    // Handler to be called on a message received
    _on = null

    // Handler to be called right before a message is sent
    _beforeSend = null

    // Handler to be called before the message is being retried
    _beforeRetry = null

    // Global handler to be called when a message delivery failed
    _onFail = null

    // Global handler to be called when a message is acknowledged
    _onAck = null

    // Global handler to be called when a message is replied
    _onReply = null

    // Retry interval
    _retryInterval = null

    // Flag indicating if the autoretry is enabled or not
    _autoRetry = null

    // Max number of auto retries
    _maxAutoRetries = null

    // Data message class definition. Any message being sent by the user
    // is considered to be data message.
    //
    // The class defines the data message structure and handlers.
    DataMessage = class {
        
        // Message payload to be sent
        payload = null

        // Message metadata that can be used for application specific purposes
        metadata = null

        // Number of attempts to send the message
        tries = null

        // Individual message timeout
        _timeout = null

        // Message sent time
        _sent = null

        // Time of the next retry
        _nextRetry = null

        // Handler to be called when the message delivery failed
        _onFail = null

        // Handler to be called when the message is acknowledged
        _onAck = null

        // Handler to be called when the message is replied
        _onReply = null

        // Data message constructor
        // Constructor is not going to be called from the user code
        //
        // Parameters:
        //      id              Data message unique identifier
        //      name            Data message name
        //      data            The actual data being sent
        //      timeout         Individual message timeout
        //      metadata        Data message metadata
        //
        // Returns:             Data message object created
        function constructor(id, name, data, timeout, metadata) {
            payload = {
                "id": id,
                "type": MM_MESSAGE_NAME_DATA,
                "name": name,
                "data": data,
                "created": time()
            }
            this.tries = 0
            this.metadata = metadata
            this._timeout = timeout
            this._nextRetry = 0
        }

        // Sets the message-local handler to be called when an error occurs
        //
        // Parameters:
        //      handler         The handler to be called. It has signature:
        //                      handler(message, reason, retry)
        //                      Paremeters:
        //                          message         The message that received an error
        //                          reason          The error reason details
        //                          retry           The function to be called
        //
        // Returns:             Nothing
        function onFail(handler) {
            _onFail = handler
        }

        // Sets the message-local handler to be called on the message acknowledgement
        //
        // Parameters:
        //      handler         The handler to be called. It has signature:
        //                      handler(message)
        //                      Paremeters:
        //                          message         The message that was acked
        //
        // Returns:             Nothing
        function onAck(handler) {
            _onAck = handler
        }

        // Sets the message-local handler to be called when the message is replied
        //
        // Parameters:
        //      handler         The handler to be called. It has signature:
        //                      handler(message, response), where
        //                          message         The message that received a reply
        //                          response        Response received as reply
        //
        // Returns:             Nothing
        function onReply(handler) {
            _onReply = handler
        }
    }

    // MessageManager constructor
    //
    // Parameters:
    //      config          Configuration of the message manager
    //
    // Returns:             MessageManager object created
    function constructor(config = null) {
        if (!config) {
            config = {}
        }

        _nextId = 0
        _sentQueue  = {}
        _retryQueue = {}

        // Handlers
        _on = {}

        // Partner initialization
        _partner = _isAgent() ? device : agent;
        _partner.on(MM_MESSAGE_NAME_ACK, _onAckReceived.bindenv(this))
        _partner.on(MM_MESSAGE_NAME_DATA, _onDataReceived.bindenv(this))
        _partner.on(MM_MESSAGE_NAME_NACK, _onNackReceived.bindenv(this))
        _partner.on(MM_MESSAGE_NAME_REPLY, _onReplyReceived.bindenv(this))

        // Read configuration
        _cm             = "connectionManager" in config ? config["connectionManager"] : null
        _debug          = "debug"             in config ? config["debug"]             : MM_DEFAULT_DEBUG
        _retryInterval  = "retryInterval"     in config ? config["retryInterval"]     : MM_DEFAULT_RETRY_INTERVAL
        _msgTimeout     = "messageTimeout"    in config ? config["messageTimeout"]    : MM_DEFAULT_MSG_TIMEOUT
        _autoRetry      = "autoRetry"         in config ? config["autoRetry"]         : MM_DEFAULT_AUTO_RETRY
        _maxAutoRetries = "maxAutoRetries"    in config ? config["maxAutoRetries"]    : MM_DEFAULT_MAX_AUTO_RETRIES
    }

    // Sends data message
    //
    // Parameters:
    //      name            Name of the message to be sent
    //      data            Data to be sent
    //      timeout         Individual message timeout
    //      metadata        Data message metadata
    //      handlers        onAck, onFail and onReply handlers for this message
    //                         for more details, please see DataMessage
    //
    // Returns:             The data message object created
    function send(name, data = null, timeout = null, metadata = null, handlers = null) {
        local msg = DataMessage(_getNextId(), name, data, timeout, metadata)
        // Process per-message handlers
        if (handlers && handlers.len() > 0) {
            local onAck   = "onAck"   in handlers ? handlers["onAck"]   : null
            local onFail  = "onFail"  in handlers ? handlers["onFail"]  : null
            local onReply = "onReply" in handlers ? handlers["onReply"] : null

            onAck   && msg.onAck(onAck)
            onFail  && msg.onFail(onFail)
            onReply && msg.onReply(onReply)
        }
        return _send(msg)
    }

    // Sets the handler which will be called before a message is sent
    //
    // Parameters:
    //      handler         The handler to be called before send. The handler's signature:
    //                          handler(message, enqueue, dispose), where
    //                              message         The message to be sent
    //                              enqueue         Callback which when called
    //                                              makes the message appended to the
    //                                              retry queue for later processing
    //                                              enqueue() has no arguments
    //                              dispose         Callback which when called
    //                                              disposes the message
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
    //                              skip            Skip retry attempt and leave the message
    //                                              in the retry queue for now
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

    // Sets the handler to be called when an error occurs
    //
    // Parameters:
    //      handler         The handler to be called. It has signature:
    //                      handler(message, reason, retry)
    //                      Paremeters:
    //                          message         The message that received an error
    //                          reason          The error reason details
    //                          retry           The function to be called
    //
    // Returns:             Nothing
    function onFail(handler) {
        _onFail = handler
    }

    // Sets the handler to be called on the message acknowledgement
    //
    // Parameters:
    //      handler         The handler to be called. It has signature:
    //                      handler(message)
    //                      Paremeters:
    //                          message         The message that was acked
    //
    // Returns:             Nothing
    function onAck(handler) {
        _onAck = handler
    }

    // Sets the handler to be called when the message is replied
    //
    // Parameters:
    //      handler         The handler to be called. It has signature:
    //                      handler(message, response), where
    //                          message         The message that received a reply
    //                          response        Response received as reply
    //
    // Returns:             Nothing
    function onReply(handler) {
        _onReply = handler
    }

    // Returns the overall number of pending messages
    // (either waiting for acknowledgement or hanging in the retry queue)
    //
    // Parameters:
    //
    // Returns:             The number of all the pending messages
    function getPendingCount() {
        return _sentQueue.len() + _retryQueue.len()
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
        _log("_isConnected returns: " + connected);
        return connected
    }

    // The sent and reply queues processor
    // Handles timeouts, does resent, etc.
    //
    // Parameters:    
    //
    // Returns:             Nothing
    function _processQueues() {
        // Clean up the timer
        _queueTimer = null

        // Process timed out messages from the sent (waiting for ack) queue
        local t = time()
        foreach (id, msg in _sentQueue) {
            local timeout = msg._timeout ? msg._timeout : _msgTimeout
            if (t - msg._sent > timeout) {
                _callOnErr(msg, MM_ERR_TIMEOUT);
                delete _sentQueue[id]
            }
        }

        // Process retry message queue
        foreach (id, msg in _retryQueue) {
            if (t >= msg._nextRetry) {
                _retry(msg)
            }
        }
    }

    // The sent and reply queues processor
    // Handles timeouts, tries, etc.
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
                                _processQueues.bindenv(this))
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
        _log("Making attempt to send: " + msg.payload.data)
        local payload = msg.payload
        if (_isConnected() && !_partner.send(MM_MESSAGE_NAME_DATA, payload)) {
            // The message was successfully sent
            // Update the sent time
            msg._sent = time()
            _sentQueue[payload["id"]] <- msg
            // Make sure the timer is running
            _startTimer()
        } else {
            _log("Oops, no connection");
            // Presumably there is a connectivity issue, 
            // enqueue for further retry
            _callOnErr(msg, MM_ERR_NO_CONNECTION)
        }
    }

    // tries to send the message, and executes the beforeRerty handler
    //
    // Parameters:          Message to be resent
    //
    // Returns:             Nothing
    function _retry(msg) {
        _log("Retrying to send: " + msg.payload.data)

        local send = true
        local payload = msg.payload

        if (_isFunc(_beforeRetry)) {
            _beforeRetry(msg,
                function/*skip*/(interval = null) {
                    msg._nextRetry = time() + (interval ? interval : _retryInterval)
                    send = false
                },
                function/*dispose*/() {
                    // User requests to dispose the message, so drop it on the floor
                    delete _retryQueue[payload["id"]]
                    send = false
                }
            )
        }

        if (send) {
            msg.tries++
            delete _retryQueue[payload["id"]]
            _sendMessage(msg)
        }
    }

    // Calls the before send handler and sends the message
    //
    // Parameters:          Message to be resent
    //
    // Returns:             The message
    function _send(msg) {
        local send = true
        if (_isFunc(_beforeSend)) {
            _beforeSend(msg,
                function/*enqueue*/() {
                    _enqueue(msg)
                    send = false
                },
                function/*dispose*/() {
                    send = false
                }
            )
        }

        if (send) {
            _sendMessage(msg)
        }
        return msg
    }

    // A handler for message received (agent/device.on) events
    //
    // Parameters:          Message payload received
    //
    // Returns:             Nothing
    function _onDataReceived(payload) {

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
                handler(payload, function/*reply*/(data = null) {
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
    function _onAckReceived(payload) {
        local id = payload["id"]
        if (id in _sentQueue) {
            local msg = _sentQueue[id]

            _isFunc(msg._onAck) && msg._onAck(msg)
            _isFunc(_onAck) && _onAck(msg)

            // Delete the acked message from the queue
            delete _sentQueue[id]
        }
    }

    // Calls an error handler if set for the message
    // with the error specified
    //
    // Parameters:
    //      msg             The message that triggered the error
    //      error           The error message
    //
    // Returns:             Nothing
    function _callOnErr(msg, error) {

        local hasHandler = false
        local checkAndCall = function(f) {
            if (_isFunc(f)) {
                hasHandler = true
                f(msg, error, function/*retry*/(interval = null) {
                    msg._nextRetry = time() + (interval ? interval : _retryInterval)
                    _enqueue(msg)
                })
            }
        }

        checkAndCall(msg._onFail)
        checkAndCall(_onFail)

        if (!hasHandler) {
            // Error handler is not set. Let's check the autoretry.
            if (_autoRetry && (!_maxAutoRetries || msg.tries < _maxAutoRetries)) {
                msg._nextRetry = time() + _retryInterval
                _enqueue(msg)
            }
        }
    }

    // A handler for message nack events
    //
    // Parameters:          Payload containing id of the message that failed to be acknowledged
    //
    // Returns:             Nothing
    function _onNackReceived(payload) {
        local id = payload["id"]
        if (id in _sentQueue) {
            _callOnErr(_sentQueue[id], MM_ERR_NO_HANDLER)
        }
    }

    // A handler for message replies
    // Calls both user provided onAck and onReply handlers
    //
    // Parameters:          Payload containing id and response data for reply
    //
    // Returns:             Nothing
    function _onReplyReceived(payload) {
        local id = payload["id"]
        if (id in _sentQueue) {
            local msg = _sentQueue[id]

            // Make sure to call acknowledgement handlers first
            _isFunc(msg._onAck) && msg._onAck(msg)
            _isFunc(_onAck) && _onAck(msg)

            // Then call the global handlers
            _isFunc(msg._onReply) && msg._onReply(msg, payload["data"])
            _isFunc(_onReply) && _onReply(msg, payload["data"])

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
