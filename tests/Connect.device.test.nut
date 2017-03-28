// Copyright (c) 2017 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

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