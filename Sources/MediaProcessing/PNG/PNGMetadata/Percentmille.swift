extension PNGMetadata {
    /// A rational percentmille value.
    struct Percentmille: AdditiveArithmetic, ExpressibleByIntegerLiteral {
        /// The numerator of this percentmille value.
        ///
        /// The numerical value of this percentmille instance is this integer
        /// divided by `100000`.
        var points:Int

        /// A percentmille value of zero.
        static let zero: Self = 0

        /// Creates a percentmille value with the given numerator.
        ///
        /// The numerical value of this percentmille value will be the given
        /// numerator divided by `100000`.
        /// -   Parameter points:
        ///     The numerator.
        init<T>(_ points:T) where T:BinaryInteger {
            self.points = .init(points)
        }

        /// Creates a percentmille value using the given integer literal as
        /// the numerator.
        ///
        /// The provided integer literal is *not* the numerical value of the
        /// created percentmille value. It will be interpreted as the numerator
        /// of a rational value.
        /// -   Parameter integerLiteral:
        ///     The integer literal.
        init(integerLiteral:Int) {
            self.init(integerLiteral)
        }

        /// Adds two percentmille values and produces their sum.
        /// -   Parameter lhs:
        ///     The first value to add.
        /// -   Parameter rhs:
        ///     The second value to add.
        /// -   Returns:
        ///     The sum of the two given percentmille values.
        static func + (lhs: Self, rhs: Self) -> Self {
            .init(lhs.points + rhs.points)
        }

        /// Adds two percentmille values and stores the result in the
        /// left-hand-side variable.
        /// -   Parameter lhs:
        ///     The first value to add.
        /// -   Parameter rhs:
        ///     The second value to add.
        static func += (lhs: inout Self, rhs: Self) {
            lhs.points += rhs.points
        }
        /// Subtracts one percentmille value from another and produces their
        /// difference.
        /// -   Parameter lhs:
        ///     A percentmille value.
        /// -   Parameter rhs:
        ///     The value to subtract from `lhs`.
        /// -   Returns:
        ///     The difference of the two given percentmille values.
        static func - (lhs: Self, rhs: Self) -> Self {
            .init(lhs.points - rhs.points)
        }
        /// Subtracts one percentmille value from another and stores the
        /// result in the left-hand-side variable.
        /// -   Parameter lhs:
        ///     A percentmille value.
        /// -   Parameter rhs:
        ///     The value to subtract from `lhs`.
        static func -= (lhs: inout Self, rhs: Self) {
            lhs.points -= rhs.points
        }
    }
}

extension PNGMetadata.Percentmille: CustomStringConvertible {
    var description: String {
        "\(self.points) / 100000"
    }
}
