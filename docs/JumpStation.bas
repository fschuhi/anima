Attribute VB_Name = "JumpStation"
Option Explicit

Private m_frmSelector As UserFormSelector
Private m_jumpTargets As Object  ' Dictionary<String, String>
Private m_sheetSpecificTargets As Object  ' Dictionary<String, String>

Private m_cBackSheets As Collection


'*************************************
' helpers
'*************************************

Private Sub EnsureSheetIsVisible(ws As Worksheet)
    ' Check if the sheet is hidden or very hidden and make it visible
    If ws.Visible = xlSheetVeryHidden Then
        ws.Visible = xlSheetVisible
    ElseIf ws.Visible = xlSheetHidden Then
        ws.Visible = xlSheetVisible
    End If
End Sub



'*************************************
' jump stack
'*************************************

Sub SaveSheetToJumpStack(wsSheetToSave As Worksheet)
    If wsSheetToSave Is Nothing Then Set wsSheetToSave = ActiveSheet
    If m_cBackSheets Is Nothing Then Set m_cBackSheets = New Collection
    m_cBackSheets.Add wsSheetToSave
End Sub

Sub JumpBack()
    If m_cBackSheets Is Nothing Then GoTo no_sheet
    If m_cBackSheets.Count = 0 Then GoTo no_sheet
    Dim wsBack As Worksheet: Set wsBack = m_cBackSheets(m_cBackSheets.Count)
    EnsureSheetIsVisible wsBack
    wsBack.Activate
    m_cBackSheets.Remove m_cBackSheets.Count
    Exit Sub
no_sheet:
    MsgBox "no sheet to jump back to", vbExclamation
End Sub



Private Sub JumpToAddressOnClipboard()
    Dim sLinkedAddress As String: sLinkedAddress = Trim(GetFromClipboard())
    JumpToLinkedAddress sLinkedAddress
End Sub


Private Sub JumpToAddressInComment()
    Dim sComment As String: sComment = GetComment(Selection.Cells(1))
    Dim cCommentLines As Collection: Set cCommentLines = StringToCollection(sComment, Chr(13) & Chr(10))
    If cCommentLines.Count = 0 Then GoTo no_link
    Dim sLinkedAddress As String: sLinkedAddress = Trim(cCommentLines(1))
    If sLinkedAddress = "" Then GoTo no_link
    JumpToLinkedAddress sLinkedAddress
    Exit Sub
no_link:
    MsgBox "no LINK in first line of comment", vbExclamation
End Sub


Private Sub JumpToLinkedAddress(sLinkedAddress As String)
    Dim wsBack As Worksheet: Set wsBack = ActiveSheet

    Dim sAddress As String: sAddress = Trim(sLinkedAddress)

    ' ((YTNNBMD))
    sAddress = RegMatch(sAddress, "^([Ll][Ii][Nn][Kk]:?)? *=? *(.+)", 2)
    Dim sSheet As String: sSheet = RegMatch(sAddress, "^'(\[.+?\])?([^']+?)'!(.+$)", 2)
    If Not SheetExists(sSheet) Then GoTo err
    Dim sLocalAddress As String: sLocalAddress = RegMatch(sAddress, "^'(\[.+?\])?([^']+?)'!(.+$)", 3)

    On Error GoTo err
    Dim wsJumpTarget As Worksheet: Set wsJumpTarget = Worksheets(sSheet)
    EnsureSheetIsVisible wsJumpTarget
    wsJumpTarget.Activate
    Range(sLocalAddress).Select
    Application.GoTo Reference:=Range(sLocalAddress), Scroll:=True
    On Error GoTo 0

    SaveSheetToJumpStack wsBack
    GoTo done
err:
    MsgBox "no address on clipboard", vbExclamation
    wsBack.Activate
done:
End Sub



'*************************************
' jumpstation
'*************************************

Private Sub AddJumpTarget(requiredSheet As String, ByVal Text As String, ByVal subName As String)
    If requiredSheet = "" Then
        m_jumpTargets.Add Text, subName
    Else
        m_sheetSpecificTargets.Add Text, requiredSheet & "|" & subName
    End If
End Sub


Sub ShowJumpStation()
    Dim frm As UserFormSelector
    Set frm = UserFormSelector.CreateWithoutOptions(m_frmSelector)

    ' Initialize jump targets
    Set m_jumpTargets = New Dictionary
    Set m_sheetSpecificTargets = New Dictionary

    ' Add always-available jump targets
    AddJumpTarget "", "Goto Intro", "Intro"
    AddJumpTarget "", "Goto Comments", "> comments <"
    AddJumpTarget "", "Goto Waterfall", "Waterfall summary"
    AddJumpTarget "", "Goto Base Case", "Base Case"
    AddJumpTarget "", "Goto KID", "KID"
    AddJumpTarget "", "Goto Assumptions - general", "Assumptions - general"
    AddJumpTarget "", "Goto Portfolio model", "Portfolio model"
    AddJumpTarget "", "Goto Statistics - overall", "Statistics - overall"
    AddJumpTarget "", "Goto Statistics - stages", "Statistics - stages"
    AddJumpTarget "", "Goto Calibrate", "Calibrate"

    AddJumpTarget "", "Reset checks", "ResetChecks"

    ' Add WS_Work-specific jump targets
    'AddJumpTarget WS_Work, "Add row", "AddRowToPomodoroTable"

    ' Add WS_Sudoku-specific jump targets
    'AddJumpTarget WS_Sudoku, "Initialize puzzle", "Sudoku_InitializePuzzle"

    ' Add visible options to form
    Dim key As Variant

    ' Add global targets
    For Each key In m_jumpTargets.Keys
        frm.AddOption AsString(key)
    Next key

    ' Add sheet-specific targets
    For Each key In m_sheetSpecificTargets.Keys
        Dim parts As Variant
        parts = Split(m_sheetSpecificTargets(key), "|")
        If LCase(ActiveSheet.Name) = LCase(parts(0)) Then
            frm.AddOption AsString(key)
        End If
    Next key

    ' Show form and handle selection
    frm.Show
    If frm.Cancel Then Exit Sub

    ' Execute selected target
    If m_jumpTargets.Exists(frm.Selection) Then
        ExecuteTarget m_jumpTargets(frm.Selection)
    ElseIf m_sheetSpecificTargets.Exists(frm.Selection) Then
        Dim selectedParts As Variant
        selectedParts = Split(m_sheetSpecificTargets(frm.Selection), "|")
        ExecuteTarget selectedParts(1)
    Else
        MsgBox "?"
    End If
End Sub


Private Function ExecuteTarget(v)
    If SheetExists(v) Then
        SaveSheetToJumpStack ActiveSheet
        Dim ws As Worksheet: Set ws = Worksheets(v)
        EnsureSheetIsVisible ws
        ws.Activate
    Else
        Application.Run v
    End If
End Function
