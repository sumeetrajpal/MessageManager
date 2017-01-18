device.on("MM_DATA", function(payload) {
    device.send("MM_REPLY", {
        "id" : payload["id"],
        "data" : payload["data"]
    })
})