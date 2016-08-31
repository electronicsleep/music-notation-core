//
//  Staff.swift
//  MusicNotationKit
//
//  Created by Kyle Sherman on 6/15/15.
//  Copyright © 2015 Kyle Sherman. All rights reserved.
//

public struct Staff {

    public let clef: Clef
    public let instrument: Instrument
    public private(set) var measureCount: Int = 0

    internal private(set) var notesHolders: [NotesHolder] = [] {
        didSet {
            recomputeMeasureIndexes()
        }
    }

    private var measureIndexes: [(notesHolderIndex: Int, repeatMeasureIndex: Int?)] = []

    public init(clef: Clef, instrument: Instrument) {
        self.clef = clef
        self.instrument = instrument
    }

    public mutating func appendMeasure(_ measure: Measure) {
        notesHolders.append(measure)
        measureCount += measure.measureCount
    }

    public mutating func appendRepeat(_ repeatedMeasures: MeasureRepeat) {
        notesHolders.append(repeatedMeasures)
        measureCount += repeatedMeasures.measureCount
    }

    /**
     Inserts a measure at the given index.

     If the given index falls on a `MeasureRepeat`, there are 3 things that can happen:

     1. If the index is the beginning of a repeat, see the `beforeRepeat` parameter.
     2. If the index is within the original measure(s) to be repeated, the `newMeasure`
     will be inserted into the repeat. The new measure is therefore repeated
     `MeasureRepeat.repeatCount` times.
     3. If the index is within the repeated portion, the insert will fail, because
     the repeated measures are immutable. See `MeasureRepeat`.
     
     - parameter measure: The measure to be inserted.
     - parameter index: The index where the measure should be inserted.
     - parameter beforeRepeat: Default value is true. This parameter is only used if the given index is
        the beginning of a repeat. True if you want the measure to be inserted before the repeat. False
        when you want the measure to be inserted into the repeat at the given index.
     - throws:
        - `StaffError.measureIndexOutOfRange`
        - `StaffError.noRepeatToInsertInto`
        - `StaffError.hasToInsertIntoRepeatIfIndexIsNotFirstMeasureOfRepeat`
        - `StaffError.internalError`
        - `MeasureRepeatError.indexOutOfRange`
        - `MeasureRepeatError.cannotModifyRepeatedMeasures`
     */
    public mutating func insertMeasure(_ measure: Measure, at index: Int, beforeRepeat: Bool = true) throws {
        let notesHolderIndex = try notesHolderIndexFromMeasureIndex(index)
        // Not a repeat, just insert
        if notesHolderIndex.repeatMeasureIndex == nil {
            notesHolders.insert(measure, at: notesHolderIndex.notesHolderIndex)
            measureCount += measure.measureCount
        } else {
            if beforeRepeat && notesHolderIndex.repeatMeasureIndex == 0 {
                notesHolders.insert(measure, at: notesHolderIndex.notesHolderIndex)
                measureCount += measure.measureCount
                return
            }
            // Is a repeat, so insert if it is one of the measures to be repeated
            guard var measureRepeat = notesHolders[notesHolderIndex.notesHolderIndex] as? MeasureRepeat,
                let repeatMeasureIndex = notesHolderIndex.repeatMeasureIndex else {
                assertionFailure("Index translation showed should be a repeat, but it's not")
                throw StaffError.internalError
            }
            try measureRepeat.insertMeasure(measure, at: repeatMeasureIndex)
            notesHolders[notesHolderIndex.notesHolderIndex] = measureRepeat
        }
    }

    /**
     Inserts a `MeasureRepeat` at the given index. If there is already a repeat at the given index,
     this will fail.
     
     - parameter measureRepeat: The repeat to insert.
     - parameter index: The index where the repeat should be inserted.
     - throws:
        - `StaffError.measureIndexOutOfRange`
        - `StaffError.cannotInsertRepeatWhereOneAlreadyExists`
     */
    public mutating func insertRepeat(_ measureRepeat: MeasureRepeat, at index: Int) throws {
        let notesHolderIndex = try notesHolderIndexFromMeasureIndex(index)
        guard notesHolderIndex.repeatMeasureIndex == nil || notesHolderIndex.repeatMeasureIndex == 0 else {
            throw StaffError.cannotInsertRepeatWhereOneAlreadyExists
        }
        notesHolders.insert(measureRepeat, at: notesHolderIndex.notesHolderIndex)
        measureCount += measureRepeat.measureCount
    }

    /**
     Replaces the measure at the given index with a new measure. The measure index takes into consideration
     repeats. Therefore, the index is the actual index of the measure as it were played.

     - parameter measureIndex: The index of the measure to replace.
     - parameter newMeasure: The new measure to replace the old one.
     - throws:
         - `StaffError.repeatedMeasureCannotBeModified` if the measure is a repeated measure.
         - `StaffError.internalError` if index translation doesn't work properly.
     */
    public mutating func replaceMeasure(at measureIndex: Int, with newMeasure: Measure) throws {
        let (notesHolderIndex, repeatMeasureIndex) = try notesHolderIndexFromMeasureIndex(measureIndex)
        let newNotesHolder: NotesHolder
        if let repeatMeasureIndex = repeatMeasureIndex {
            guard (try? mutableMeasureFromNotesHolderIndex(notesHolderIndex, repeatMeasureIndex: repeatMeasureIndex)) != nil else {
                throw StaffError.repeatedMeasureCannotBeModified
            }
            guard var measureRepeat = notesHolders[notesHolderIndex] as? MeasureRepeat else {
                assertionFailure("Index translation showed should be a repeat, but it's not")
                throw StaffError.internalError
            }
            measureRepeat.measures[repeatMeasureIndex] = newMeasure
            newNotesHolder = measureRepeat
        } else {
            newNotesHolder = newMeasure
        }
        notesHolders[notesHolderIndex] = newNotesHolder
    }

    /**
     Ties a note to the next note.

     - parameter noteIndex: The index of the note in the specified measure to begin the tie.
     - parameter measureIndex: The index of the measure that contains the note at which the tie should begin.
     - throws:
         - `StaffError.noteIndexoutOfRange`
         - `StaffError.noNextNoteToTie` if the note specified is the last note in the staff.
         - `StaffError.measureIndexOutOfRange`
         - `StaffError.repeatedMeasureCannotHaveTie` if the index for the measure specified refers to a measure that is
            a repeat of another measure.
         - `StaffError.internalError`, `MeasureError.internalError` if the function has an internal implementation error.
         - `MeasureError.noteIndexOutOfRange`
     */
    public mutating func startTieFromNote(at noteIndex: Int, inMeasureAt measureIndex: Int) throws {
        try modifyTieForNote(at: noteIndex, inMeasureAt: measureIndex, removeTie: false)
    }

    /**
     Removes the tie beginning at the note at the specified index.

     - parameter noteIndex: The index of the note in the specified measure where the tie begins.
     - parameter measureIndex: The index of the measure that contains the note at which the tie begins.
     - throws:
         - `StaffError.noteIndexoutOfRange`
         - `StaffError.noNextNoteToTie` if the note specified is the last note in the staff.
         - `StaffError.measureIndexOutOfRange`
         - `StaffError.repeatedMeasureCannotHaveTie` if the index for the measure specified refers to a measure that is
            a repeat of another measure.
         - `MeasureError.noteIndexOutOfRange`
         - `StaffError.internalError`, `MeasureError.internalError` if the function has an internal implementation error.
     */
    public mutating func removeTieFromNote(at noteIndex: Int, inMeasureAt measureIndex: Int) throws {
        try modifyTieForNote(at: noteIndex, inMeasureAt: measureIndex, removeTie: true)
    }

    /**
     - parameter measureIndex: The index of the measure to return.
     - returns An `ImmutableMeasure` at the given index within the staff.
     - throws:
        - `StaffError.measureIndexOutOfRange`
        - `StaffError.internalError` if the function has an internal implementation error.
     */
    public func measure(at measureIndex: Int) throws -> ImmutableMeasure {
        let (notesHolderIndex, repeatMeasureIndex) = try notesHolderIndexFromMeasureIndex(measureIndex)
        if let measureRepeat = notesHolders[notesHolderIndex] as? MeasureRepeat,
            let repeatMeasureIndex = repeatMeasureIndex {
            return measureRepeat.expand()[repeatMeasureIndex]
        } else if let measure = notesHolders[notesHolderIndex] as? ImmutableMeasure {
            return measure
        }
        throw StaffError.internalError
    }

    /**
     - parameters measureIndex: The index of a measure that is either repeated or is one of the repeated measures.
     - returns A `MeasureRepeat` that contains the measure(s) that are repeated as well as the repeat count. Returns nil
     if the measure at the specified index is not part of repeat.
     - throws:
        - `StaffError.measureIndexOutOfRange`
        - `StaffError.internalError` if the function has an internal implementation error.
     */
    public func measureRepeat(at measureIndex: Int) throws -> MeasureRepeat? {
        let (notesHolderIndex, _) = try notesHolderIndexFromMeasureIndex(measureIndex)
        return notesHolders[notesHolderIndex] as? MeasureRepeat
    }

    internal func notesHolderAtMeasureIndex(_ measureIndex: Int) throws -> NotesHolder {
        let (notesHolderIndex, _) = try notesHolderIndexFromMeasureIndex(measureIndex)
        return notesHolders[notesHolderIndex]
    }

    private mutating func modifyTieForNote(at noteIndex: Int, inMeasureAt measureIndex: Int, removeTie: Bool) throws {
        let notesHolderIndex = try notesHolderIndexFromMeasureIndex(measureIndex)

        // Ensure first measure information provided is valid for tie
        var firstMeasure = try mutableMeasureFromNotesHolderIndex(notesHolderIndex.notesHolderIndex, repeatMeasureIndex: notesHolderIndex.repeatMeasureIndex)
        guard noteIndex < firstMeasure.noteCount else {
            throw StaffError.noteIndexOutOfRange
        }

        if noteIndex == firstMeasure.noteCount - 1 {
            let secondNotesHolderIndex: (notesHolderIndex: Int, repeatMeasureIndex: Int?)
            do {
                secondNotesHolderIndex = try notesHolderIndexFromMeasureIndex(measureIndex + 1)
            } catch {
                throw StaffError.noNextNoteToTie
            }
            var secondMeasure = try mutableMeasureFromNotesHolderIndex(
				secondNotesHolderIndex.notesHolderIndex,
				repeatMeasureIndex: secondNotesHolderIndex.repeatMeasureIndex)
            guard secondMeasure.noteCount > 0 else {
                throw StaffError.noNextNoteToTie
            }

			if !removeTie {
				let firstNoteIndex = try firstMeasure.noteCollectionIndexFromNoteIndex(noteIndex)
				var firstNote: Note
				if firstNoteIndex.tupletIndex == nil {
					firstNote = firstMeasure.notes[firstNoteIndex.noteIndex] as! Note
				} else {
					guard let tuplet = firstMeasure.notes[firstNoteIndex.noteIndex] as? Tuplet,
						let tupletIndex = firstNoteIndex.tupletIndex else {
							assertionFailure("Index translation showed should be a tuplet, but it's not")
							throw StaffError.internalError
					}
					firstNote = tuplet.notes[tupletIndex]
				}
				
				let secondNoteIndex = try secondMeasure.noteCollectionIndexFromNoteIndex(0)
				var secondNote: Note
				if secondNoteIndex.tupletIndex == nil {
					secondNote = secondMeasure.notes[secondNoteIndex.noteIndex] as! Note
				} else {
					guard let tuplet = secondMeasure.notes[secondNoteIndex.noteIndex] as? Tuplet,
						let tupletIndex = secondNoteIndex.tupletIndex else {
							assertionFailure("Index translation showed should be a tuplet, but it's not")
							throw StaffError.internalError
					}
					secondNote = tuplet.notes[tupletIndex]
				}
				
				if firstNote.tones != secondNote.tones {
					throw StaffError.noSameNoteTie
				}
			}
			
			// Modify tie and update second Measure. The first Measure update is done later.
			try firstMeasure.modifyTie(at: noteIndex, requestedTieState: removeTie ? nil : .begin )
			try secondMeasure.modifyTie(at: 0, requestedTieState: removeTie ? nil : .end)
			try replaceMeasure(at: measureIndex + 1, with: secondMeasure)
        } else {
			if removeTie {
				try firstMeasure.removeTie(at: noteIndex)
			} else {
				try firstMeasure.startTie(at: noteIndex)
			}
        }
		
        try replaceMeasure(at: measureIndex, with: firstMeasure)
    }

    internal func notesHolderIndexFromMeasureIndex(_ index: Int) throws -> (notesHolderIndex: Int, repeatMeasureIndex: Int?) {
        guard index >= 0 && index < measureCount else { throw StaffError.measureIndexOutOfRange }
        return measureIndexes[index]
    }

    private mutating func recomputeMeasureIndexes() {
        measureIndexes = []
        for (i, notesHolder) in notesHolders.enumerated() {
            switch notesHolder {
            case is Measure:
                measureIndexes.append((notesHolderIndex: i, repeatMeasureIndex: nil))
            case let measureRepeat as MeasureRepeat:
                for j in 0..<measureRepeat.measureCount {
                    measureIndexes.append((notesHolderIndex: i, repeatMeasureIndex: j))
                }
            default:
                assertionFailure("NotesHolders should only be Measure or MeasureRepeat")
                continue
            }
        }
    }

    private func mutableMeasureFromNotesHolderIndex(_ notesHolderIndex: Int, repeatMeasureIndex: Int?) throws -> Measure {
        let notesHolder = notesHolders[notesHolderIndex]
        // Ensure first measure information provided is valid for tie
        if let repeatMeasureIndex = repeatMeasureIndex {
            // If repeatMeasureIndex is not nil, check if measure is not a repeated one
            // If it's not, check if noteIndex is less than count of measure
            guard let measureRepeat = notesHolder as? MeasureRepeat else {
                assertionFailure("Index translation showed should be a repeat, but it's not")
                throw StaffError.internalError
            }
            guard let mutableMeasure = measureRepeat.expand()[repeatMeasureIndex] as? Measure else {
                throw StaffError.repeatedMeasureCannotHaveTie
            }
            return mutableMeasure
        } else {
            // If repeatMeasureIndex is nil, check if the noteIndex is less than note count of measure
            assert(notesHolder.measureCount == 1, "Index translation showed should be a single measure, but it's not")
            guard let immutableMeasure = notesHolder as? ImmutableMeasure else {
                throw StaffError.internalError
            }
            if let mutableMeasure = immutableMeasure as? Measure {
                return mutableMeasure
            } else {
                assertionFailure("If not a repeated measure, should be a mutable measure")
                throw StaffError.internalError
            }
        }
    }
}

public enum StaffError: Error {
    case noteIndexOutOfRange
    case measureIndexOutOfRange
    case noNextNoteToTie
    case noNextNote
    case notBeginningOfTie
    case repeatedMeasureCannotHaveTie
	case noSameNoteTie
    case measureNotPartOfRepeat
    case repeatedMeasureCannotBeModified
    case cannotInsertRepeatWhereOneAlreadyExists
    case noRepeatToInsertInto
    case hasToInsertIntoRepeatIfIndexIsNotFirstMeasureOfRepeat
    case internalError
}

extension Staff: CustomDebugStringConvertible {
    public var debugDescription: String {
        let notesDescription = notesHolders.map { $0.debugDescription }.joined(separator: ", ")
        
        return "staff(\(clef) \(instrument) \(notesDescription))"
    }
}
