# MessageManager Library 0.0.1 (Alpha)

MessageManager is framework for asynchronous agent and device communication. 
The library is a successor of Bullwinkle and is designed to fix some of the 
function issues of it's predecessor.

## Some MessageManager Features

- Optimized usage of system timers;
- Optimized traffic used for service messages (replies and acknowledgements);
- Connection awareness (leveraging ConnectionManager) and device/agent.send status 
to avoid useless operations when there is no connection with the corresponding party;
- Separation of the message payload from the wrapping structure that may be used and 
extended for application specific purposes and is not sent over the wire;
- Per-message timeout;
- API hooks to control outgoing messages. This may be used to adjust application 
specific timestamps, introduce additional fields and meta-information or enqueue message 
to delay delivery if needed);
- API hooks to control retry process. This may be used to dispose the message if it's 
outdated or update the meta-information (the number of retries).

## API Overview
- [MessageManager](#mmanager) - The core library - used to add/remove handlers, and send messages
    - [MessageManager.send](#mmanager_send) - Sends the data message
    - [MessageManager.beforeSend](#mmanager_before_send) - Sets the callback which will be called before a message is sent
    - [MessageManager.beforeRetry](#mmanager_before_retry) - Sets the callback which will be called before a message is retried
    - [MessageManager.on](#mmanager_on) - Sets the callback, which will be called when a message with the specified name is received
    - [MessageManager.getSizeOfWaitingForAck](#mmanager_get_size_of_waiting_for_ack) - Returns the size of the pending for ack message queue
    - [MessageManager.getSizeOfRetry](#mmanager_get_size_of_retry) - Returns the size of the retry queue

### Details and Usage
TBD

## Examples
TBD

## License

Bullwinkle is licensed under the [MIT License](./LICENSE).
