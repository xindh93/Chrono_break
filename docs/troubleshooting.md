# Troubleshooting

## Rojo reports `expected "," or "}"` for `src/startergui/Sidebar/init.screen.gui.json`
Rojo surfaces this parse error when the JSON file was hand-edited and a comma was
accidentally removed. The Stats row we added to the sidebar defines two siblings,
`Icon` and `Label`, under `$children`. There must be a comma after the `Icon`
block so the parser knows another child follows. If the comma after the block at
lines 242-251 is missing, Rojo reaches the `"Label"` key, still thinks it is
parsing the previous object, and throws `expected "," or "}"`. Restoring the
comma or pulling the committed version of the file resolves the issue.
