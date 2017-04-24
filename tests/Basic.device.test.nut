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


class BasicTestCase extends ImpTestCase {

    static MESSAGE_NAME = "test";
    static TOTAL_OFFLINE_MESSAGE_COUNT = 10;
    static TOTAL_ONLINE_MESSAGE_COUNT  = 10;

    _cm = null;
    _mm = null;

    _numOfAcks = null;
    _numOfFails = null;
    _numOfReplies = null;
    _numOfTimeouts = null;
    _numOfBeforeSends = null;
    _numOfBeforeRetries = null;

    _numOfLocalAcks = null;
    _numOfLocalFails = null;
    _numOfLocalReplies = null;
    _numOfLocalTimeouts = null;

    _handlers = null;
    _nextId = null;

    MyConnectionManager = class {

        _connected = null;
        _onDisconnect = null;
        _onConnect = null;

        function constructor() {
            _connected = true;
        }

        function isConnected() {
            return _connected;
        }

        function disconnect() {
            this._connected = false;
            _isFunc(_onDisconnect) && _onDisconnect(true);
        }

        function connect() {
            this._connected = true;
            _isFunc(_onConnect) && _onConnect();
        }

        function onDisconnect(handler) {
            _onDisconnect = handler;
        }

        function onConnect(handler) {
            _onConnect = handler;
        }

        function _isFunc(f) {
            return f && typeof f == "function";
        }
    }

    function gOnAck(msg) {
        _numOfAcks++;
    }

    function gOnFail(msg, error, retry) {
        _numOfFails++;
        retry();
    }

    function gOnReply(msg, response) {
        _numOfReplies++;
    }

    function gOnTimeout(msg, wait, fail) {
        _numOfTimeouts++;
    }

    function gBeforeSend(msg, enqueue, drop) {
        _numOfBeforeSends++;
    }

    function gBeforeRetry(msg, skip, drop) {
        _numOfBeforeRetries++;
    }

    function localOnAck(msg) {
        _numOfLocalAcks++;
    }

    function localOnFail(msg, error, retry) {
        _numOfLocalFails++;
    }

    function localOnReply(msg, response) {
        _numOfLocalReplies++;
    }

    function localOnTimeout(msg, wait, fail) {
        _numOfLocalTimeouts++;
    }

    function constructor() {
        _resetCounters();

        _nextId = 0;

        _handlers = {};
        _handlers[MM_HANDLER_NAME_ON_ACK]     <- localOnAck.bindenv(this);
        _handlers[MM_HANDLER_NAME_ON_FAIL]    <- localOnFail.bindenv(this);
        _handlers[MM_HANDLER_NAME_ON_REPLY]   <- localOnReply.bindenv(this);
        _handlers[MM_HANDLER_NAME_ON_TIMEOUT] <- localOnTimeout.bindenv(this);
    }

    function setUp() {
        _cm = MyConnectionManager();

        local config = {
            "messageTimeout"    : 10,
            "connectionManager" : _cm,
            "nextIdGenerator"   : function () {
                _nextId = (_nextId + 1) % RAND_MAX;
                return _nextId;
            }.bindenv(this)
        };

        _mm = MessageManager(config);
        _mm.onAck(gOnAck.bindenv(this));
        _mm.onFail(gOnFail.bindenv(this));
        _mm.onReply(gOnReply.bindenv(this));
        _mm.onTimeout(gOnTimeout.bindenv(this));
        _mm.beforeSend(gBeforeSend.bindenv(this));
        _mm.beforeRetry(gBeforeRetry.bindenv(this));
    }

    function _send(name, data = null, handlers = null, timeout = null, metadata = null) {
        _mm.send(name, data, handlers, timeout, metadata);
    }

    function _resetCounters() {
        _numOfAcks = 0;
        _numOfFails = 0;
        _numOfReplies = 0;
        _numOfTimeouts = 0;
        _numOfBeforeSends = 0;
        _numOfBeforeRetries = 0;

        _numOfLocalAcks = 0;
        _numOfLocalFails = 0;
        _numOfLocalReplies = 0;
        _numOfLocalTimeouts = 0;
    }

    function testDisconnectedDoesntSendMessages() {
        _resetCounters();
        _cm.disconnect();

        // Send all the messages offline
        for (local i = 0; i < TOTAL_OFFLINE_MESSAGE_COUNT; i++) {
            _send(MESSAGE_NAME);
        }

        return Promise(function(resolve, reject) {
            imp.wakeup(2, function() {
                assertEqual(0, _numOfAcks, "acks");
                assertEqual(0, _numOfReplies, "replies");
                assertEqual(0, _numOfTimeouts, "timeouts");
                assertEqual(0, _numOfBeforeRetries, "beforeRetries");
                assertEqual(TOTAL_OFFLINE_MESSAGE_COUNT, _numOfFails, "fails");
                assertEqual(TOTAL_OFFLINE_MESSAGE_COUNT, _numOfBeforeSends, "beforeSends");
                assertEqual(TOTAL_OFFLINE_MESSAGE_COUNT, _mm.getPendingCount(), "pending");

                // If both handlers are defined, the number of acks should be equal to the number of replies
                assertEqual(_numOfReplies, _numOfAcks, "acks == replies");

                // No local handlers to be called
                assertEqual(0, _numOfLocalAcks, "localAcks");
                assertEqual(0, _numOfLocalFails, "localFails");
                assertEqual(0, _numOfLocalReplies, "localReplies");
                assertEqual(0, _numOfLocalTimeouts, "localTimeouts");

                _cm.connect();
                resolve();
            }.bindenv(this));
        }.bindenv(this));
    }

    function testMessagesSent() {
        _resetCounters();
        _cm.connect();

        local minValue = 1000;

        // Send all the messages offline
        for (local i = 0; i < TOTAL_ONLINE_MESSAGE_COUNT; i++) {
            _send(MESSAGE_NAME, minValue + i, _handlers);
            imp.sleep(0.01);
        }

        return Promise(function(resolve, reject) {
            imp.wakeup(5, function() {

                assertEqual(0, _numOfFails, "num of fails");
                assertEqual(0, _numOfTimeouts, "num of timeouts");
                assertEqual(0, _numOfBeforeRetries, "num of beforeRetries");
                assertEqual(TOTAL_ONLINE_MESSAGE_COUNT, _numOfAcks, "num of acks");
                assertEqual(TOTAL_ONLINE_MESSAGE_COUNT, _numOfReplies, "num of replies");
                assertEqual(TOTAL_ONLINE_MESSAGE_COUNT, _numOfBeforeSends, "num of beforeSends");

                // Message local handlers should be called the same number of times as the global ones
                assertEqual(_numOfAcks, _numOfLocalAcks, "acks == localAcks");
                assertEqual(_numOfFails, _numOfLocalFails, "fails == localFails");
                assertEqual(_numOfReplies, _numOfLocalReplies, "replies == localReplies");
                assertEqual(_numOfTimeouts, _numOfLocalTimeouts, "timeouts == localTimeouts");

                resolve();
            }.bindenv(this));
        }.bindenv(this));
    }

    function tearDown() {
        // Clean up the test
    }
}