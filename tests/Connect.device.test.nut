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


class ConnectTestCase extends ImpTestCase {

    _cm = null;
    _mm = null;

    _partnerConnected = false;
    _onConnectedReply = null;

    MyConnectionManager = class {

        _connected = null;
        _onConnect = null;
        _onDisconnect = null;

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

    function onPartnerConnected(reply) {
        _partnerConnected = true
    }

    function onConnectedReply(data) {
        _onConnectedReply = data;
    }

    function setUp() {
        // agent.on("MM_CONNECT", function(payload) {
        // });

        _cm = MyConnectionManager();

        local config = {
            "connectionManager"  : _cm,
            "onConnectedReply"   : onConnectedReply.bindenv(this),
            "onPartnerConnected" : onPartnerConnected.bindenv(this),
            "maxMessageRate"     : 20
        };

        _mm = MessageManager(config);
    }

    function testConnected() {
        return Promise(function(resolve, reject) {
            imp.wakeup(1, function() {
                assertTrue(_partnerConnected, "Partner connected");
                assertEqual(_onConnectedReply, "No messages", "Connected reply");
                resolve();
            }.bindenv(this));
        }.bindenv(this));
    }
}