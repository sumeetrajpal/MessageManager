// Copyright (c) 2017 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class ThrottlingDeviceTestCase extends ImpTestCase {

    static MESSAGE_NAME        = "test";
    static MAX_RATE_LIMIT      = 10;
    static RETRY_INTERVAL_SEC  = 1;
    static TOTAL_MESSAGES_SENT = 20;

    _mm = null;
    _numOfAcks = null;
    _numOfFailures = null;

    function onAck(msg) {
        _numOfAcks++;
    }

    function onFail(msg, error, retry) {
        if (error == "Maximum sending rate exceeded") {
            _numOfFailures++;
        }
        retry();
    }

    function _send(name, data = null, handlers = null, timeout = null, metadata = null) {
        _mm.send(name, data, handlers, timeout, metadata);
    }

    function setUp() {
        _resetCounters();

        local config = {
            "maxMessageRate" : MAX_RATE_LIMIT,
            "retryInterval"  : RETRY_INTERVAL_SEC
        };

        _mm = MessageManager(config);
        _mm.onAck(onAck.bindenv(this));
        _mm.onFail(onFail.bindenv(this));
    }

    function _resetCounters() {
        _numOfAcks = 0;
        _numOfFailures = 0;
    }

    function testConnected() {
        _resetCounters();

        // Send all the messages offline
        for (local i = 0; i < TOTAL_MESSAGES_SENT; i++) {
            _send(MESSAGE_NAME, i);
            imp.sleep(0.01);
        }

        return Promise(function(resolve, reject) {
            imp.wakeup(3, function() {
                assertEqual(TOTAL_MESSAGES_SENT - MAX_RATE_LIMIT, _numOfFailures, "Number of rate limits: " + _numOfFailures);
                // assertTrue(_numOfFailures >= TOTAL_MESSAGES_SENT - MAX_RATE_LIMIT, "Number of rate limits: " + _numOfFailures);
                assertEqual(TOTAL_MESSAGES_SENT, _numOfAcks, "Number of ACKs: " + _numOfAcks);
                resolve();
            }.bindenv(this));
        }.bindenv(this));
    }
}
