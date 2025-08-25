extension F14 {
    @safe struct District {
        typealias Row = (key: UInt32, value: UInt16, displaced: UInt16)

        let base: UnsafeMutableRawPointer
    }
}

extension F14.District {
    var header: SIMD16<UInt8> {
        unsafe self.base.load(as: SIMD16<UInt8>.self)
    }

    var tags: UnsafeMutablePointer<UInt8> {
        unsafe self.base.bindMemory(to: UInt8.self, capacity: 14)
    }

    subscript(index: Int) -> Row {
        _read {
            yield (unsafe (self.base + (16 + 8 * index)).bindMemory(to: Row.self, capacity: 1).pointee)
        }
        nonmutating _modify {
            yield unsafe &(self.base + (16 + 8 * index)).bindMemory(to: Row.self, capacity: 1).pointee
        }
    }

    var displaced: UInt16 {
        _read {
            yield self[0].displaced
        }

        nonmutating _modify {
            yield &self[0].displaced
        }
    }
}
