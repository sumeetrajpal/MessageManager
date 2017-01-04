// Copyright (c) 2016 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// Default configuration values
// TODO: revise the values once again
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
// TODO: not sure if we want to define it here though
const MM_ERR_TIMEOUT          = "Message timeout error"
const MM_ERR_NO_HANDLER       = "No handler error"
const MM_ERR_NO_CONNECTION    = "No connection error"

class MessageManager {

    static version = [0, 0, 1];

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

    // Is debug mode enabled
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

    // Handler to be called on error when trying to resend the message
    _onRetryError = null

    // Error handler
    _onError = null

    // Acknowledgement handler
    _onAck = null

    // Reply handler
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
    _DataMessage = class {
        
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
                "created": time()
            }
            tries = 0
            metadata = {}
            _timeout = timeout
            _nextRetry = 0
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
        _partner.on(MM_MESSAGE_NAME_ACK, _onAckReceived.bindenv(this))
        _partner.on(MM_MESSAGE_NAME_DATA, _onDataReceived.bindenv(this))
        _partner.on(MM_MESSAGE_NAME_NACK, _onNackReceived.bindenv(this))
        _partner.on(MM_MESSAGE_NAME_REPLY, _onReplyReceived.bindenv(this))

        // Read configuration
        _debug          = "debug"          in config ? config["debug"]          : MM_DEFAULT_DEBUG
        _msgTimeout     = "msgTimeout"     in config ? config["msgTimeout"]     : MM_DEFAULT_MSG_TIMEOUT
        _retryInterval  = "retryInterval"  in config ? config["retryInterval"]  : MM_DEFAULT_RETRY_INTERVAL
        _autoRetry      = "autoRetry"      in config ? config["autoRetry"]      : MM_DEFAULT_AUTO_RETRY
        _maxAutoRetries = "maxAutoRetries" in config ? config["maxAutoRetries"] : MM_DEFAULT_MAX_AUTO_RETRIES
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
        return _send(msg)
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

    function onRetryError(handler) {
        _onRetryError = handler
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
    // Returns:             Nothing
    function onError(handler) {
        _onError = handler
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
    // Returns:             Nothing
    function onAcked(handler) {
        _onAck = handler
    }

    // Sets the acknowledgement handler to be called
    // when a message is acked by the corresponding party
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
            _beforeSend(msg, function/*enqueue*/() {
                _enqueue(msg)
                send = false                
            })
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
    function _onAckReceived(payload) {
        local id = payload["id"]
        if (id in _sentQueue) {
            local msg = _sentQueue[id]

            if (_isFunc(_onAck)) {
                _onAck(msg)
            }

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
        if (_isFunc(_onError)) {
            _onError(msg, error, function/*retry*/(interval = null) {
                msg._nextRetry = time() + (interval ? interval : _retryInterval)
                _enqueue(msg)
            })
        } else {
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
    //
    // Parameters:          Payload containing id and response data for reply
    //
    // Returns:             Nothing
    function _onReplyReceived(payload) {
        local id = payload["id"]
        if (id in _sentQueue) {
            local msg = _sentQueue[id]

            if (_isFunc(_onReply)) {
                _onReply(msg, payload["data"])
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
