VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} UserFormSelector
   Caption         =   "Selector"
   ClientHeight    =   4305
   ClientLeft      =   119
   ClientTop       =   462
   ClientWidth     =   4564
   OleObjectBlob   =   "UserFormSelector.frx":0000
   StartUpPosition =   1  'Fenstermitte
End
Attribute VB_Name = "UserFormSelector"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False


' 17.12.24

Option Explicit

Private m_bCancel As Boolean
Private m_sCurrentInput As String
Private m_iCurrentIndex As Integer

Public Function Create(ByRef frm As UserFormSelector, ParamArray options())
    Set frm = Nothing
    If frm Is Nothing Then
        Set frm = New UserFormSelector
        frm.Caption = "JumpStation: " & ActiveSheet.Name
        frm.Initialize options
    End If
    Set Create = frm
End Function


Public Function CreateWithoutOptions(ByRef frm As UserFormSelector)
    Set frm = Nothing
    If frm Is Nothing Then
        Set frm = New UserFormSelector
        frm.Caption = "JumpStation: " & ActiveSheet.Name
        frm.InitializeWithoutOptions
    End If
    Set CreateWithoutOptions = frm
End Function



'*************************************
' Properties
'*************************************

Public Property Get Cancel() As Boolean
    Cancel = m_bCancel
End Property

Public Property Let Cancel(ByVal bCancel As Boolean)
    m_bCancel = bCancel
End Property

Public Property Get CurrentInput() As String
    CurrentInput = m_sCurrentInput
End Property

Public Property Let CurrentInput(sCurrentInput As String)
    m_sCurrentInput = sCurrentInput
    Label1.Caption = LCase(m_sCurrentInput)
End Property

Public Property Get CurrentIndex() As Integer
    CurrentIndex = m_iCurrentIndex
End Property

Public Property Let CurrentIndex(iCurrentIndex As Integer)
    On Error GoTo done
    ListBox1.ListIndex = iCurrentIndex
    m_iCurrentIndex = iCurrentIndex
done:
End Property

Public Property Get Selection() As String
    If CurrentIndex = -1 Then
        Selection = ""
    Else
        Selection = ListBox1.List(CurrentIndex)
    End If
End Property


'*************************************
' Initialize
'*************************************

Public Sub Initialize(ParamArray aOptions())
    aOptions = ParamArrayDelegated(aOptions)

    Dim sOption
    Dim cOptions As New Collection
    Dim ixOption

    For ixOption = LBound(aOptions) To UBound(aOptions)
        sOption = Trim(aOptions(ixOption))
        If sOption <> "" Then
            cOptions.Add aOptions(ixOption)
        End If
    Next

    For ixOption = 1 To cOptions.Count
        ListBox1.AddItem cOptions(ixOption)
    Next

    Reset
End Sub

Public Sub InitializeWithoutOptions()
    Reset
End Sub

Public Sub AddOption(sOption As String)
    ListBox1.AddItem sOption
End Sub

Public Sub Reset()
    CurrentInput = ""
    Cancel = True
    CurrentIndex = -1
End Sub


'*************************************
' Search functionality
'*************************************

Private Function FindMatch(searchText As String) As Integer
    If searchText = "" Then
        FindMatch = 0
        Exit Function
    End If

    Dim i As Integer
    For i = 0 To ListBox1.ListCount - 1
        If InStr(1, LCase(ListBox1.List(i)), LCase(searchText)) > 0 Then
            FindMatch = i
            Exit Function
        End If
    Next i

    FindMatch = -1
End Function


'*************************************
' Key handling
'*************************************

Private Sub ListBox1_KeyDown(ByVal KeyCode As MSForms.ReturnInteger, ByVal Shift As Integer)
    Select Case KeyCode
        Case vbKeyEscape
            If CurrentInput = "" Then
                Cancel = True
                CurrentIndex = -1
                GoTo done
            Else
                CurrentInput = ""
                CurrentIndex = 0
            End If

        Case vbKeyReturn
            If CurrentIndex >= 0 Then
                Cancel = False
                GoTo done
            End If

        Case vbKeyBack, vbKeyLeft
            If CurrentInput <> "" Then
                CurrentInput = Left(CurrentInput, Len(CurrentInput) - 1)
                CurrentIndex = FindMatch(CurrentInput)
            End If

        Case vbKeyDown
            If CurrentIndex < ListBox1.ListCount - 1 Then
                CurrentIndex = CurrentIndex + 1
            End If

        Case vbKeyUp
            If CurrentIndex > 0 Then
                CurrentIndex = CurrentIndex - 1
            End If

        Case vbKeyHome
            CurrentIndex = 0

        Case vbKeyEnd
            CurrentIndex = ListBox1.ListCount - 1

        Case 32 To 255
            If KeyCode >= vbKeyA And KeyCode <= vbKeyZ Then
                CurrentInput = CurrentInput & Chr(KeyCode)
            ElseIf KeyCode = 32 Then
                CurrentInput = CurrentInput & " "
            ElseIf KeyCode = 186 Then
                CurrentInput = CurrentInput & "Ö"
            ElseIf KeyCode = 192 Then
                CurrentInput = CurrentInput & "Ü"
            ElseIf KeyCode = 222 Then
                CurrentInput = CurrentInput & "Ä"
            End If

            Dim newIndex As Integer
            newIndex = FindMatch(CurrentInput)
            If newIndex >= 0 Then
                CurrentIndex = newIndex
            End If
    End Select

    KeyCode = 0
    Exit Sub

done:
    Me.Hide
End Sub

Private Sub UserForm_Click()

End Sub
