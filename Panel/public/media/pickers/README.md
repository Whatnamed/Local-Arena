# Picker thumbnails

These 192 glove/music thumbnails accompany the existing Local Arena catalogs.
They are display assets, not game payload. Original catalog URLs, resolved source
URLs, file sizes and SHA-256 hashes are in `src/data/bundledPickerMedia.json`.

Artwork belongs to Valve and the respective music/artwork owners. Existing
source attribution is retained; the Chocolate Chesterfield render is sourced
from the catalog's CSGOSKINS.GG URL. This packaging does not claim authorship
or relicense the artwork under the source-code license.

Refresh with `pwsh -File scripts/cache-picker-media.ps1` from the repository.
Steam economy thumbnails use its 256px rendition; oversized source PNGs are
resized to fit 256px. Total catalog budget is 20 MiB. Build checks verify every
file's PNG signature, length and hash without needing a live CDN.
