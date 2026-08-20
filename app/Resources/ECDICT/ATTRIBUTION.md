# ECDICT attribution

SideLingo's offline English–Chinese dictionary is generated from the ECDICT
repository by Linwei (skywind3000):

- Source: https://github.com/skywind3000/ECDICT
- Pinned source commit: `bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b`
- Included upstream files: `stardict.7z` (`stardict.csv`) and `lemma.en.txt`
- Upstream repository license: MIT; the full license text is included beside
  this file.

The generated SQLite database preserves ECDICT's lexical fields and adds a
normalized lookup key, lookup indexes, and a lemma mapping table. The upstream
README describes ECDICT as an aggregation built
from several dictionaries, corpora, public word lists, automated collection,
and community contributions. SideLingo has verified the repository-level MIT
license and preserves attribution, but has not independently reconstructed the
provenance and licensing chain of every individual lexical record.
