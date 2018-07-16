# export-ulysses

Exports your Ulysses library as markdown files.

- Preserves bold, italics, links, code blocks, and strikethroughs.
- Annotations precede their attached text by a colon, so an annotation on the word **bloom** with text "See wordnik for more" becomes:
  > See wordnik for more: bloom.
- Exported markdown files have creation and modification dates that match your notes.
- A meta text section is included (by default, can be turned off) in each note wherein export date, creation/modification dates, note keywords, and attachment filenames are recorded.

## Installing

export-ulysses is written in Swift 4.2 (I was curious). You’ll need to [install Xcode](https://developer.apple.com/xcode/) to build it.

```
git clone git@github.com:kevboh/export-ulysses.git
cd export-ulysses
swift run export-ulysses --help
```

If you plan to do this often, you may want to build a release binary with `swift build -c release` and copy it into your PATH.

## Usage (--help)

```
Usage:

    $ export-ulysses <input> <output>

Arguments:

    input - The path to your Ulysses notes. See README for hints on what this might be.
    output - The path you want to export notes to.

Options:
    --keep-groups [default: false] - Create directories for each Ulysses Group, and export notes into them.
    --skip-meta [default: false] - Don’t append Ulysses keywords, attachment info, create date, and modify date to files. Files will still have the correct system create and modify dates.
    --verbose [default: false] - Log export activity and debugging statements.
```

### Okay, give me those input hints

If you don’t use iCloud, your notes are probably at `~/Library/Containers/com.soulmen.ulysses3/Data/Documents/Library/`.

If you do use iCloud, your notes are probably at `~/Library/Mobile Documents/X5AZV975AG~com~soulmen~ulysses3/Documents/Library/`. You can’t view that directory in the Finder, so if you need to hunt for it you should probably do so in Terminal.app.

## Some Caveats!

1.  While this tool works on my Ulysses library, I built it specifically to crash when something unexpected pops up. A Ulysses-flavored Markdown feature/tag I never happened to use, for example. If that happens to you, please file an issue or, better yet, a PR!
2.  Images are not currently supported, only logged in note text as having been present, e.g. `(image with ID xyz)`. I have a pretty good idea of how to support them, though, so if you need them I could probably make it happen.
3.  File attachments are not supported, but their file names are logged in the appended meta text.
