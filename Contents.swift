import Foundation

protocol Fillable {
    associatedtype Value
    
    static func empty() -> Value
}

protocol Storeable {
    associatedtype Item: Fillable
    
    var value: Item.Value { get }
    var version: Int { get }
    
    init(value: Item.Value, version: Int)
    
    init()
}

struct StoreableItem<FillableItem: Fillable>: Storeable {
    typealias Item = FillableItem
    
    let value: FillableItem.Value
    let version: Int
    
    init(value: FillableItem.Value, version: Int){
        self.value = value
        self.version = version
    }
    
    init(){
        self.init(value: FillableItem.empty(), version: 0)
    }
}

protocol Subscribable {
    associatedtype Stream
    
    func subscribe(observer: @escaping (Stream) -> Void) -> Void
    
    func map<NextStream>(transformation: @escaping (Stream) -> NextStream) -> Observable<Stream, NextStream>
    
    func withLatestFrom<OtherIn, OtherOut, CombinedStream>(stream: Observable<OtherIn, OtherOut>, combine: @escaping (Stream, OtherOut) -> CombinedStream) -> Observable<Stream, CombinedStream>
    
    func latest() -> Stream
}

class Observable<In, Out>: Subscribable {
    typealias Streamable = Out
    
    private let chainSubscribe: (@escaping (In) -> Void) -> Void
    private let transform: (In) -> Out
    private var shelf: [Out] = []
    
    // PROBLEM CHILD
    static func combineLatest<In1, Out1, In2, Out2, Combined>(stream1: Observable<In1, Out1>, stream2: Observable<In2, Out2>, combine: @escaping (Out1, Out2) -> Combined) -> Observable<Combined, Combined>{
        let subscribeToBoth = {(observer: @escaping (Combined) -> Void) -> Void in
            stream1.withLatestFrom(stream: stream2, combine: combine).subscribe(observer: observer)
            let reversedCombine: (Out2, Out1) -> Combined = {value2, value1 in return combine(value1, value2)}
            stream2.withLatestFrom(stream: stream1, combine: reversedCombine).subscribe(observer: observer)
        }
        return Observable<Combined, Combined>(chainSubscribe: subscribeToBoth, transform: {(value: Combined) -> Combined in value})
    }
    
    init(chainSubscribe: @escaping (@escaping (In) -> Void) -> Void, transform: @escaping (In) -> Out){
        self.chainSubscribe = chainSubscribe
        self.transform = transform
        chainSubscribe({(value: In) -> Void in self.shelf.append(transform(value))})
    }
    
    func next(observer: @escaping (Out) -> Void) -> (In) -> Void{
        return {(value: In) -> Void in
            let transformedValue = self.transform(value)
            self.shelf.append(transformedValue)
            observer(transformedValue)
        }
    }
    
    func subscribe(observer: @escaping (Out) -> Void) -> Void {
        self.chainSubscribe(self.next(observer: observer))
    }
    
    func map<NextOut>(transformation: @escaping (Out) -> NextOut) -> Observable<Out, NextOut>{
        return Observable<Out, NextOut>(chainSubscribe: self.subscribe, transform: transformation)
    }
    
    func withLatestFrom<OtherIn, OtherOut, Combined>(stream: Observable<OtherIn, OtherOut>, combine: @escaping (Out, OtherOut) -> Combined) -> Observable<Out, Combined>{
        let nextWithLatest: (Out) -> Combined = {(_ next: Out) -> Combined in
            return combine(next, stream.latest())
        }
        return Observable<Out, Combined>(chainSubscribe: self.subscribe, transform: nextWithLatest)
    }
    
    func latest() -> Out {
        return shelf[shelf.count - 1]
    }
}

class Store<Stored: Storeable> {
    typealias Streamable = Stored
    
    var shelf: [Stored]
    private var observers: [(Stored) -> Void]
    
    init(){
        self.shelf = [Stored()]
        self.observers = []
    }
    
    func open() -> Observable<Stored, Stored>{
        return Observable<Stored, Stored>(chainSubscribe: self.subscribe, transform: {(value: Stored) -> Stored in value})
    }
    
    func store(value: Stored.Item.Value){
        let newItem = Stored(value: value, version: shelf.count)
        shelf.append(newItem)
        self.observers.forEach({(observer) -> Void in
            observer(newItem)
        })
    }
    
    func subscribe(observer: @escaping (Stored) -> Void) -> Void{
        self.observers.append(observer)
        observer(self.latest())
    }
    
    func latest() -> Stored {
        return shelf[shelf.count - 1]
    }
}

// ABOVE THIS LINE EVERYTHING IS GENERIC. BELOW IS CONCRETE.

struct FillableString: Fillable {
    typealias Value = String
    
    static func empty() -> String {
        return ""
    }
}
typealias StoreableString = StoreableItem<FillableString>
typealias StringStore = Store<StoreableString>

func testCombineLatest() -> [Bool] {
    let gossipStore = StringStore()
    let businessStore = StringStore()
    let areYouSerious: (StoreableString, StoreableString) -> Bool = {(business: StoreableString, gossip: StoreableString) -> Bool in
        return business.value.characters.count > gossip.value.characters.count
    }
    let stream1: Observable<StoreableString, StoreableString> = businessStore.open()
    let stream2: Observable<StoreableString, StoreableString> = gossipStore.open()
    let areYouSeriousObservable: Observable<Bool, Bool> = Observable.combineLatest(stream1: stream1, stream2: stream2, combine: areYouSerious)
    var seriousnesses = [Bool]()
    areYouSeriousObservable.subscribe(observer: {(newSeriousness: Bool) -> Void in
        seriousnesses.append(newSeriousness)
    })
    
    gossipStore.store(value: "Dude where's your car?")
    businessStore.store(value: "Looking at the combined quarterly reports...")
    gossipStore.store(value: "Dude where's your car? Dude where's my car? Dude where's your car?")
    
    return seriousnesses
}

// SHOULD EQUAL [false, false, true, false]
testCombineLatest()

