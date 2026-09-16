import XCTest
import Captures

final class CaptureTextTests: XCTestCase {
    func testSourceCodeIsCode() {
        let samples = [
            "func add(_ a: Int) -> Int {\n    return a + 1\n}",
            "{\n  \"name\": \"piper\",\n  \"tags\": [1, 2]\n}",
            "def add(a):\n    return a + 1\n",
            "swift build \\\n  --configuration release \\\n  --arch arm64",
            "\tif x {\n\t\ty()\n\t}"
        ]
        for sample in samples {
            XCTAssertTrue(CaptureText.looksLikeCode(sample), sample)
        }
    }

    func testProseAndListsAreNotCode() {
        let samples = [
            "",
            "let x = 1;",
            "Buy milk.\nCall the bank about the card.",
            "Groceries:\n- eggs\n  - brown\n- bread",
            "Steps:\n1. Open the app\n  2. Copy a note\n3. Save it",
            "A long paragraph that the reader copied from a web page (with an aside)\nand a second line of the same paragraph."
        ]
        for sample in samples {
            XCTAssertFalse(CaptureText.looksLikeCode(sample), sample)
        }
    }

    func testFirstLineSkipsBlankLinesAndIndentation() {
        XCTAssertEqual(CaptureText.firstLine("\n  \n    let x = 1\n}"), "let x = 1")
        XCTAssertEqual(CaptureText.firstLine("   "), "")
    }
}
