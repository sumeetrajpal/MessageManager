// MIT License
//
// Copyright 2016-2017 Electric Imp
//
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.


class ThrottlingDeviceTestCase extends ImpTestCase {

    static MESSAGE_NAME        = "test";
    static MAX_RATE_LIMIT      = 17;
    static RETRY_INTERVAL_SEC  = 1;
    static TOTAL_MESSAGES_SENT = 33;

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
                assertEqual(MAX_RATE_LIMIT, _numOfAcks, "Number of ACKs: " + _numOfAcks);
                resolve();
            }.bindenv(this));
        }.bindenv(this));
    }
}
