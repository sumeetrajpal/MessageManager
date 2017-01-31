// Copyright (c) 2017 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class ThrottlingDeviceTestCase extends ImpTestCase {

    static MESSAGE_NAME = "test";
    static TOTAL_MESSAGES_SENT = 20;

    _mm = null;
    _numOfAcks = null;
    _numOfRateLimits = null;

    function onAck(msg) {
        _numOfAcks++;
    }

    function onFail(msg, error, retry) {
        if (error == "Maximum sending rate exceeded") {
            _numOfRateLimits++;    
        }
        retry();
    }

    function _send(name, data = null, handlers = null, timeout = null, metadata = null) {
        _mm.send(name, data, handlers, timeout, metadata);
    }

    function setUp() {
        _resetCounters();

        local config = {
            "retryInterval" : 1 // sec
        };

        _mm = MessageManager(config);
        _mm.onAck(onAck.bindenv(this));
        _mm.onFail(onFail.bindenv(this));
    }

    function _resetCounters() {
        _numOfAcks = 0;
        _numOfRateLimits = 0;
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
                assertEqual(10, _numOfRateLimits, "Number of rate limits");
                assertEqual(TOTAL_MESSAGES_SENT, _numOfAcks, "Number of ACKs");
                resolve();
            }.bindenv(this));
        }.bindenv(this));
    }
}
