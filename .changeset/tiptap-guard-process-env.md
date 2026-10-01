---
'@octanejs/tiptap': patch
---

Guard the `process.env.NODE_ENV` read in `useEditor` so programs without a
`process` global or Node types can consume the package's shipped sources.
---
