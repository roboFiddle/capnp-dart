@0xa074fbab61132cbd;

interface Subscription {}

interface Publisher {
    subscribe @0 (subscriber: Subscriber) -> (subscription: Subscription);
}

interface Subscriber {
    pushMessage @0 (message: Text) -> ();
}