; EsyType's additions to Tauri's NSIS installer (docs/plans/installer-plan.md, section 5).
; Tauri's uninstaller removes the program, its shortcut and Apps-list entry, and, when "Delete the application data"
; is ticked, its own browser-engine folder. EsyType's data lives in %LOCALAPPDATA%\EsyAI\<product>, which Tauri does
; not know about, and EsyType writes its own start-with-Windows entry: both are handled here.
;
; Only EsyType's own files are deleted, one by one, never a whole folder tree: RMDir /r would follow folder links
; out of the folder (tauri-apps/tauri#16323) and would delete files that are not EsyType's.
; During an upgrade Tauri runs the old uninstaller with /UPDATE ($UpdateMode = 1): nothing here runs then.

; After installing: point start-with-Windows at this copy, unless the user turned it off (EsyType's default is on, and
; it writes the same entry itself when it starts). Done here too because an interactive upgrade can run the old
; uninstaller, which removes the entry, and the user may untick "Run" on the last page.
!macro NSIS_HOOK_POSTINSTALL
  StrCpy $1 1
  SetShellVarContext current
  ClearErrors
  FileOpen $2 "$LOCALAPPDATA\EsyAI\${PRODUCTNAME}\settings.json" r
  ${IfNot} ${Errors}
    ${Do}
      ClearErrors
      FileRead $2 $3
      ${If} ${Errors}
        ${ExitDo}
      ${EndIf}
      ; one setting per line; spacing differs (EsyType's writer, or an older file), so compare with spaces removed
      ${WordReplace} $3 " " "" "+" $4
      ${WordReplace} $4 "$\t" "" "+" $4
      StrCpy $5 $4 22
      ${If} $5 == '"start_with_windows":f'
        StrCpy $1 0
      ${EndIf}
    ${Loop}
    FileClose $2
  ${EndIf}
  ${If} $1 = 1
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${PRODUCTNAME}" '"$INSTDIR\${MAINBINARYNAME}.exe" --minimized'
  ${EndIf}
!macroend

!macro NSIS_HOOK_POSTUNINSTALL
  ${If} $UpdateMode <> 1
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${PRODUCTNAME}"

    ${If} $DeleteAppDataCheckboxState = 1
      SetShellVarContext current
      StrCpy $0 "$LOCALAPPDATA\EsyAI\${PRODUCTNAME}"
      Delete "$0\settings.json"
      Delete "$0\settings.json.tmp"
      Delete "$0\settings.damaged-*.json"
      Delete "$0\esytype.db"
      Delete "$0\esytype.db-wal"
      Delete "$0\esytype.db-shm"
      Delete "$0\esytype.db.bak-v*"
      Delete "$0\esytype.db.restoring"
      Delete "$0\restore-pending.esytype-backup"
      Delete "$0\before-restore\before-restore*.esytype-backup"
      Delete "$0\before-restore\before-restore*.esytype-backup.partial"
      RMDir "$0\before-restore"
      ; downloaded speech models in the default models folder (a folder moved elsewhere is not touched)
      Delete "$0\models\ggml-*.bin"
      Delete "$0\models\ggml-*.bin.partial"
      Delete "$0\models\.esytype-write-test"
      RMDir "$0\models"
      ; the folders go only if nothing else is left in them
      RMDir "$0"
      RMDir "$LOCALAPPDATA\EsyAI"
    ${EndIf}
  ${EndIf}
!macroend
