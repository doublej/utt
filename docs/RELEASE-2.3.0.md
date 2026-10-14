Hold a key, speak, release. The text lands at your cursor. Nothing leaves the
machine.

This one is about choice. There are three new Parakeet models, the Model page
now tells you what each one is good at before you download it, and a model you
no longer use can be removed from the same page.

## Three new models

All three are versions of Parakeet v3, the model utt has used from the start,
retrained by people outside NVIDIA. They run on the Neural Engine like the rest.

- **Parakeet Accurate** (Moondream's Parakeet Ultra) makes fewer mistakes than
  v3 in every language it knows, at the same speed. It is about 630 MB, the
  largest Parakeet.
- **Parakeet Compact** (Moondream's Parakeet Redux) is v3 at a third of the
  size, about 220 MB. It is slower and does worse with background noise. The
  first time it loads, macOS spends about ten minutes preparing it for the
  Neural Engine. After that it loads in seconds.
- **Parakeet English** (Fermion Research's Phonon-2) is English only and lighter
  than v3, and it punctuated our test recording most neatly.

Parakeet Standard (v3) is still the default. Nothing changes unless you pick
something else.

## Every model, described

Each model now has a plain name that says what it is for, such as Standard,
Accurate, Compact or Quick, with the original name in its description. Under
the description, four ratings of one to four dots compare it with every other
model on both engines: speed, accuracy, how many languages it knows, and how
little room it takes. Its language and size sit beside them.

The engine switch now just says Parakeet, since it runs seven models.

## On this Mac, or still to download

The Model page is split in two. The first list is what is already on this Mac,
the second is what would have to be downloaded first, so you can see what a
choice costs before you make it.

A downloaded model you are not using has a trash button. It moves the model's
files to the Trash, so a mistake can be undone until you empty it. The model you
are using has no trash button, since it is the one in memory.

When you pick a model that is already downloaded, the page now says **Loading**
beside the timer. A model on disk still has to be read into memory before it can
listen.

## Updating

Nothing you have set up needs redoing. The models are credited under
**About → Attribution**, as their licence asks.
