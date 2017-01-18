class MessageManagerTestCase extends ImpTestCase {

    static MESSAGE_NAME = "test"
    static TOTAL_OFFLINE_MESSAGE_COUNT = 10
    static TOTAL_ONLINE_MESSAGE_COUNT = 100

    _cm = null
    _mm = null

    _numOfAcks = null
    _numOfFails = null
    _numOfReplies = null
    _numOfOnTimeouts = null
    _numOfBeforeSends = null
    _numOfBeforeRetries = null

    _numOfLocalAcks = null

    _handlers = null

    MyConnectionManager = class {

        _connected = null
        _onDisconnect = null
        _onConnect = null

        function constructor() {
            _connected = true
        }

        function isConnected() {
            return _connected
        }

        function disconnect() {
            this._connected = false
            _isFunc(_onDisconnect) && _onDisconnect(true)
        }

        function connect() {
            this._connected = true
            _isFunc(_onConnect) && _onConnect()
        }

        function onDisconnect(handler) {
            _onDisconnect = handler
        }

        function onConnect(handler) {
            _onConnect = handler
        }

        function _isFunc(f) {
            return f && typeof f == "function"
        }
    }

    function gOnAck(msg) {
        _numOfAcks++
    }

    function gOnFail(msg, error, retry) {
        _numOfFails++
        retry()
    }

    function gOnReply(msg, response) {
        _numOfReplies++
    }

    function gOnTimeout(msg, wait, fail) {
        _numOfOnTimeouts++
    }

    function gBeforeSend(msg, enqueue, drop) {
        _numOfBeforeSends++
    }

    function gBeforeRetry(msg, skip, drop) {
        _numOfBeforeRetries++
    }

    function localOnAck(msg) {
        if (msg.payload.data >= 1000) {
            _numOfLocalAcks++
        }
    }

    function localOnFail(msg, error, retry) {
    }

    function localOnReply(msg, response) {
    }

    function localOnTimeout(msg, wait, fail) {
    }

    function constructor() {
        _numOfAcks = 0
        _numOfFails = 0
        _numOfReplies = 0
        _numOfOnTimeouts = 0
        _numOfBeforeSends = 0
        _numOfBeforeRetries = 0

        _numOfLocalAcks = 0

        _handlers = {}
        _handlers[MM_HANDLER_NAME_ON_ACK]     <- localOnAck.bindenv(this)
        _handlers[MM_HANDLER_NAME_ON_FAIL]    <- localOnFail.bindenv(this)
        _handlers[MM_HANDLER_NAME_ON_REPLY]   <- localOnReply.bindenv(this)
        _handlers[MM_HANDLER_NAME_ON_TIMEOUT] <- localOnTimeout.bindenv(this)
    }

    function setUp() {
        _cm = MyConnectionManager()

        local config = {
            "messageTimeout"    : 10,
            "connectionManager" : _cm
        }

        _mm = MessageManager(config)
        _mm.onAck(gOnAck.bindenv(this))
        _mm.onFail(gOnFail.bindenv(this))
        _mm.onReply(gOnReply.bindenv(this))
        _mm.onTimeout(gOnTimeout.bindenv(this))
        _mm.beforeSend(gBeforeSend.bindenv(this))
        _mm.beforeRetry(gBeforeRetry.bindenv(this))
    }

    function send(name, data = null, timeout = null, metadata = null, handlers = null) {
        _mm.send(name, data, timeout, metadata, handlers)
    }

    function testDisconnectedDoesntSendMessages() {
        local totalCount = TOTAL_OFFLINE_MESSAGE_COUNT
        _cm.disconnect()

        // Send all the messages offline
        for (local i = 0; i < totalCount; i++) {
            send(MESSAGE_NAME)
        }

        return Promise(function(resolve, reject) {
            imp.wakeup(2, function() {
                assertEqual(0, _numOfAcks)
                assertEqual(0, _numOfReplies)
                assertEqual(0, _numOfOnTimeouts)
                assertEqual(totalCount, _numOfFails)
                assertEqual(totalCount, _numOfBeforeSends)
                assertEqual(totalCount, _mm.getPendingCount())

                _cm.connect()
                resolve()
            }.bindenv(this))
        }.bindenv(this))
    }

    function testMessagesSent() {

        local totalCount = TOTAL_ONLINE_MESSAGE_COUNT
        _cm.connect()

        local minValue = 1000

        // Send all the messages offline
        for (local i = 0; i < totalCount; i++) {
            send(MESSAGE_NAME, minValue + i, null, null, _handlers)
            imp.sleep(0.01)
        }

        return Promise(function(resolve, reject) {
            imp.wakeup(5, function() {
                assertTrue(TOTAL_ONLINE_MESSAGE_COUNT <= _numOfLocalAcks)
                assertTrue(TOTAL_ONLINE_MESSAGE_COUNT <= _numOfReplies)
                assertEqual(0, _numOfOnTimeouts)
                resolve()
            }.bindenv(this))
        }.bindenv(this))
    }

    function tearDown() {
        // Clean up the test
    }
}