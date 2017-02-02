// Copyright (c) 2017 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

device.on("MM_DATA", function(payload) {
    device.send("MM_REPLY", {
        "id" : payload["id"],
        "data" : payload["data"]
    });
});

device.on("MM_CONNECT", function(payload) {
    sendConnected();
    device.send("MM_CONNECT_REPLY", {
        "data" : "No messages"
    });
})

function sendConnected() {
    device.send("MM_CONNECT", null);
}
