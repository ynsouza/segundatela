' Inicia a Tela do Cliente sem abrir janela preta
' Se um programa recém-atualizado falhar ao iniciar, volta sozinho para a versão anterior
Set fso = CreateObject("Scripting.FileSystemObject")
pasta = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & pasta & "\TelaCliente.ps1"""
codigo = sh.Run(cmd, 0, True)

pendente = pasta & "\atualizacao-pendente"
anterior = pasta & "\versao-anterior\TelaCliente.ps1"
If codigo <> 0 And fso.FileExists(pendente) And fso.FileExists(anterior) Then
  fso.CopyFile anterior, pasta & "\TelaCliente.ps1", True
  fso.DeleteFile pendente
  Set reg = fso.OpenTextFile(pasta & "\registro.log", 8, True)
  reg.WriteLine Now & " | Programa novo falhou ao iniciar (codigo " & codigo & "). Voltei para a versao anterior."
  reg.Close
  sh.Run cmd, 0, False
End If
