Unicode true

!define APP_NAME  "AION 2 DPS Meter"
!define APP_EXE   "aion2_dpsmeter.exe"
!define PUBLISHER "aion2_dpsmeter"
!define REG_KEY   "Software\Microsoft\Windows\CurrentVersion\Uninstall\AION2DPSMeter"

; VERSION é passado via makensis /DVERSION=v0.1.0
!ifndef VERSION
  !define VERSION "dev"
!endif

Name "${APP_NAME} ${VERSION}"
OutFile "aion2_dpsmeter-${VERSION}-setup.exe"
InstallDir "$PROGRAMFILES64\AION2 DPS Meter"
InstallDirRegKey HKLM "Software\AION2DPSMeter" "Install_Dir"
RequestExecutionLevel admin
ShowInstDetails show

Page directory
Page instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  ; Copia todos os arquivos da pasta dist/ (exe + DLLs + data/)
  File /r "dist\*"

  ; Atalho Desktop
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" \
    "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

  ; Atalho Start Menu
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" \
    "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Desinstalar.lnk" \
    "$INSTDIR\uninstall.exe"

  ; Registro (Add/Remove Programs)
  WriteRegStr   HKLM "${REG_KEY}" "DisplayName"      "${APP_NAME}"
  WriteRegStr   HKLM "${REG_KEY}" "UninstallString"  '"$INSTDIR\uninstall.exe"'
  WriteRegStr   HKLM "${REG_KEY}" "InstallLocation"  "$INSTDIR"
  WriteRegStr   HKLM "${REG_KEY}" "Publisher"        "${PUBLISHER}"
  WriteRegStr   HKLM "${REG_KEY}" "DisplayVersion"   "${VERSION}"
  WriteRegDWORD HKLM "${REG_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${REG_KEY}" "NoRepair" 1

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  RMDir /r "$INSTDIR\data"
  Delete "$INSTDIR\*.exe"
  Delete "$INSTDIR\*.dll"
  RMDir  "$INSTDIR"

  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APP_NAME}"

  DeleteRegKey HKLM "${REG_KEY}"
  DeleteRegKey HKLM "Software\AION2DPSMeter"
SectionEnd
