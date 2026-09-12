# Raw evidence status

All user-supplied evidence visible in the troubleshooting conversation has been inventoried and hashed. The repo's manifest records filenames, byte sizes, SHA-256 hashes and duplicate groups.

## Duplicate evidence

The repeated `a/b/c/d/e/f/g/h/i` EVTX uploads were checked by SHA-256. The duplicate copies are byte-identical to their originals. `1111.txt` and `1111(1).txt` are also byte-identical. The manifest retains every original filename so the upload history is auditable without pretending duplicate bytes are distinct evidence.

## Binary upload limitation in this snapshot

The GitHub connector available to this ChatGPT session can create repository text and Git blobs from supplied string content, but it does not accept a local sandbox file as an upload parameter. Streaming all of the tens of megabytes of EVTX/images through model text would be unsafe and impractical.

Therefore this Git snapshot contains:

- complete analytical conclusions and corrections;
- extracted critical evidence from the raw logs;
- a SHA-256 manifest covering every mounted user evidence file;
- the conversation records in redacted/text form where practical;
- a repeatable collection script.

A lossless archive of the complete mounted evidence set was also created in the working sandbox as `hprobook-evidence-all.tar.gz`. Its SHA-256 at creation was:

`f9c98db4983be8b8ff7b95a7a1e7251e44af2dde01a2fb9b12997fb835124aa8`

The archive intentionally uses the ChatGPT transcript export with the BitLocker recovery password redacted. Do **not** publish the exposed recovery password.

## Public-repository warning

The raw diagnostic files can contain serial numbers, device IDs, MAC addresses, SIDs and other machine-specific metadata. The repository is public, so review that exposure before manually adding the raw archive.
