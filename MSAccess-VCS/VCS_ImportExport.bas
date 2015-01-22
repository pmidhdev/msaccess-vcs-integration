Attribute VB_Name = "VCS_ImportExport"
Option Compare Database

Option Explicit
' List of lookup tables that are part of the program rather than the
' data, to be exported with source code
'Only used in ExportAllSource
Private Const INCLUDE_TABLES = ""
' This is used in ImportAllSource
Private Const DebugOutput = False
'this is used in ExportAllSource
'Causes the VCS_ code to be exported
Private Const ArchiveMyself = False

' Constants for Scripting.FileSystemObject API
Const ForReading = 1, ForWriting = 2, ForAppending = 8
Const TristateTrue = -1, TristateFalse = 0, TristateUseDefault = -2


'returns true if named module is NOT part of the VCS code
Private Function IsNotVCS(name As String) As Boolean
If name <> "VCS_ImportExport" And name <> "VCS_IE_Functions" And name <> "VCS_BasicFunctions" And name <> "VCS_Loader" And name <> "VCS_Table" Then
    IsNotVCS = True
Else
    IsNotVCS = False
End If

End Function

' Main entry point for EXPORT. Export all forms, reports, queries,
' macros, modules, and lookup tables to `source` folder under the
' database's folder.
Public Sub ExportAllSource()
    Dim Db As Object ' DAO.Database
    Dim source_path As String
    Dim obj_path As String
    Dim qry As Object ' DAO.QueryDef
    Dim doc As Object ' DAO.Document
    Dim obj_type As Variant
    Dim obj_type_split() As String
    Dim obj_type_label As String
    Dim obj_type_name As String
    Dim obj_type_num As Integer
    Dim obj_count As Integer
    Dim ucs2 As Boolean
    Dim tblName As Variant

    Set Db = CurrentDb

    CloseFormsReports
    'InitUsingUcs2

    source_path = ProjectPath() & "source\"
    VCS_BasicFunctions.MkDirIfNotExist source_path

    Debug.Print

    obj_path = source_path & "queries\"
    VCS_BasicFunctions.ClearTextFilesFromDir obj_path, "bas"
    Debug.Print VCS_BasicFunctions.PadRight("Exporting queries...", 24);
    obj_count = 0
    For Each qry In Db.QueryDefs
        DoEvents
        If Left(qry.name, 1) <> "~" Then
            VCS_IE_Functions.ExportObject acQuery, qry.name, obj_path & qry.name & ".bas", VCS_BasicFunctions.UsingUcs2
            obj_count = obj_count + 1
        End If
    Next
    VCS_IE_Functions.SanitizeTextFiles obj_path, "bas"
    Debug.Print "[" & obj_count & "]"

    obj_path = source_path & "tables\"
    VCS_BasicFunctions.ClearTextFilesFromDir obj_path, "txt"
    If (Len(Replace(INCLUDE_TABLES, " ", "")) > 0) Then
        Debug.Print VCS_BasicFunctions.PadRight("Exporting tables...", 24);
        obj_count = 0
        For Each tblName In Split(INCLUDE_TABLES, ",")
            DoEvents
            VCS_Table.ExportTableData CStr(tblName), obj_path
            If Len(Dir(obj_path & tblName & ".txt")) > 0 Then
                obj_count = obj_count + 1
            End If
        Next
        Debug.Print "[" & obj_count & "]"
    End If

    For Each obj_type In Split( _
        "forms|Forms|" & acForm & "," & _
        "reports|Reports|" & acReport & "," & _
        "macros|Scripts|" & acMacro & "," & _
        "modules|Modules|" & acModule _
        , "," _
    )
        obj_type_split = Split(obj_type, "|")
        obj_type_label = obj_type_split(0)
        obj_type_name = obj_type_split(1)
        obj_type_num = Val(obj_type_split(2))
        obj_path = source_path & obj_type_label & "\"
        obj_count = 0
        VCS_BasicFunctions.ClearTextFilesFromDir obj_path, "bas"
        Debug.Print VCS_BasicFunctions.PadRight("Exporting " & obj_type_label & "...", 24);
        For Each doc In Db.Containers(obj_type_name).Documents
            DoEvents
            If (Left(doc.name, 1) <> "~") And _
               (IsNotVCS(doc.name) Or ArchiveMyself) Then
                If obj_type_label = "modules" Then
                    ucs2 = False
                Else
                    ucs2 = VCS_BasicFunctions.UsingUcs2
                End If
                VCS_IE_Functions.ExportObject obj_type_num, doc.name, obj_path & doc.name & ".bas", ucs2
                obj_count = obj_count + 1
            End If
        Next
        Debug.Print "[" & obj_count & "]"

        If obj_type_label <> "modules" Then
            VCS_IE_Functions.SanitizeTextFiles obj_path, "bas"
        Else
            ' Make sure all modules find their needed references
            If obj_count > 0 Then ExportReferences obj_path
        End If
    Next

    
    Dim td As TableDef
    Dim tds As TableDefs
    Set tds = Db.TableDefs

    obj_type_label = "tbldef"
    obj_type_name = "Table_Def"
    obj_type_num = acTable
    obj_path = source_path & obj_type_label & "\"
    obj_count = 0
    VCS_BasicFunctions.MkDirIfNotExist Left(obj_path, InStrRev(obj_path, "\"))
    VCS_BasicFunctions.ClearTextFilesFromDir obj_path, "sql"
    Debug.Print VCS_BasicFunctions.PadRight("Exporting " & obj_type_label & "...", 24);
    
    For Each td In tds
        ' This is not a system table
        ' this is not a temporary table
        ' this is not an external table
        If Left$(td.name, 4) <> "MSys" And _
        Left(td.name, 1) <> "~" _
        And Len(td.Connect) = 0 _
        Then
            'Debug.Print
            VCS_Table.ExportTableDef Db, td, td.name, obj_path & td.name & ".sql"
            obj_count = obj_count + 1
        End If
    Next
    Debug.Print "[" & obj_count & "]"
    
    
    Debug.Print "Done."
End Sub


' Main entry point for IMPORT. Import all forms, reports, queries,
' macros, modules, and lookup tables from `source` folder under the
' database's folder.
Public Sub ImportAllSource()
    Dim Db As Object ' DAO.Database
    Dim FSO As Object
    Dim source_path As String
    Dim obj_path As String
    Dim qry As Object ' DAO.QueryDef
    Dim doc As Object ' DAO.Document
    Dim obj_type As Variant
    Dim obj_type_split() As String
    Dim obj_type_label As String
    Dim obj_type_name As String
    Dim obj_type_num As Integer
    Dim obj_count As Integer
    Dim fileName As String
    Dim obj_name As String
    Dim ucs2 As Boolean

    Set Db = CurrentDb
    Set FSO = CreateObject("Scripting.FileSystemObject")

    CloseFormsReports
    'InitUsingUcs2

    source_path = ProjectPath() & "source\"
    If Not FSO.FolderExists(source_path) Then
        MsgBox "No source found at:" & vbCrLf & source_path, vbExclamation, "Import failed"
        Exit Sub
    End If

    Debug.Print

    obj_path = source_path & "queries\"
    fileName = Dir(obj_path & "*.bas")
    If Len(fileName) > 0 Then
        Debug.Print PadRight("Importing queries...", 24);
        obj_count = 0
        Do Until Len(fileName) = 0
            DoEvents
            obj_name = Mid(fileName, 1, InStrRev(fileName, ".") - 1)
            VCS_IE_Functions.ImportObject acQuery, obj_name, obj_path & fileName, VCS_IE_Functions.UsingUcs2
            obj_count = obj_count + 1
            fileName = Dir()
        Loop
        Debug.Print "[" & obj_count & "]"
    End If

    ' restore table definitions
    obj_path = source_path & "tbldef\"
    fileName = Dir(obj_path & "*.sql")
    If Len(fileName) > 0 Then
        Debug.Print VCS_BasicFunctions.PadRight("Importing tabledefs...", 24);
        obj_count = 0
        Do Until Len(fileName) = 0
            obj_name = Mid(fileName, 1, InStrRev(fileName, ".") - 1)
            If DebugOutput Then
                If obj_count = 0 Then
                    Debug.Print
                End If
                Debug.Print "  [debug] table " & obj_name;
                Debug.Print
            End If
            VCS_Table.ImportTableDef CStr(obj_name), obj_path & fileName
            obj_count = obj_count + 1
            fileName = Dir()
        Loop
        Debug.Print "[" & obj_count & "]"
    End If
    
    ' NOW we may load data
    obj_path = source_path & "tables\"
    fileName = Dir(obj_path & "*.txt")
    If Len(fileName) > 0 Then
        Debug.Print VCS_BasicFunctions.PadRight("Importing tables...", 24);
        obj_count = 0
        Do Until Len(fileName) = 0
            DoEvents
            obj_name = Mid(fileName, 1, InStrRev(fileName, ".") - 1)
            VCS_Table.ImportTableData CStr(obj_name), obj_path
            obj_count = obj_count + 1
            fileName = Dir()
        Loop
        Debug.Print "[" & obj_count & "]"
    End If

    For Each obj_type In Split( _
        "forms|" & acForm & "," & _
        "reports|" & acReport & "," & _
        "macros|" & acMacro & "," & _
        "modules|" & acModule _
        , "," _
    )
        obj_type_split = Split(obj_type, "|")
        obj_type_label = obj_type_split(0)
        obj_type_num = Val(obj_type_split(1))
        obj_path = source_path & obj_type_label & "\"
        
        If obj_type_label = "modules" Then
            If Not ImportReferences(obj_path) Then
                Debug.Print
                Debug.Print "Info: no references file in " & obj_path
            End If
        End If
    
        
        fileName = Dir(obj_path & "*.bas")
        If Len(fileName) > 0 Then
            Debug.Print VCS_BasicFunctions.PadRight("Importing " & obj_type_label & "...", 24);
            obj_count = 0
            Do Until Len(fileName) = 0
                ' DoEvents no good idea!
                obj_name = Mid(fileName, 1, InStrRev(fileName, ".") - 1)
                If obj_type_label = "modules" Then
                    ucs2 = False
                Else
                    ucs2 = VCS_BasicFunctions.UsingUcs2
                End If
                If IsNotVCS(obj_name) Then
                    VCS_IE_Functions.ImportObject obj_type_num, obj_name, obj_path & fileName, ucs2
                    obj_count = obj_count + 1
                Else
                    If ArchiveMyself Then
                            MsgBox "Module " & obj_name & " could not be updated while running. Ensure latest version is included!", vbExclamation, "Warning"
                    End If
                End If
                fileName = Dir()
            Loop
            Debug.Print "[" & obj_count & "]"
        
        End If
    Next
    DoEvents
    Debug.Print "Done."
End Sub


' Main entry point for ImportProject.
' Drop all forms, reports, queries, macros, modules.
' execute ImportAllSource.
Public Sub ImportProject()
On Error GoTo errorHandler

    If MsgBox("This action will delete all existing: " & vbCrLf & _
              vbCrLf & _
              Chr(149) & " Forms" & vbCrLf & _
              Chr(149) & " Macros" & vbCrLf & _
              Chr(149) & " Modules" & vbCrLf & _
              Chr(149) & " Queries" & vbCrLf & _
              Chr(149) & " Reports" & vbCrLf & _
              vbCrLf & _
              "Are you sure you want to proceed?", vbCritical + vbYesNo, _
              "Import Project") <> vbYes Then
        Exit Sub
    End If

    Dim Db As DAO.Database
    Set Db = CurrentDb
    CloseFormsReports

    Debug.Print
    Debug.Print "Deleting Existing Objects"
    Debug.Print

    Dim dbObject As Object
    For Each dbObject In Db.QueryDefs
        DoEvents
        If Left(dbObject.name, 1) <> "~" Then
'            Debug.Print dbObject.Name
            Db.QueryDefs.Delete dbObject.name
        End If
    Next

    Dim objType As Variant
    Dim objTypeArray() As String
    Dim doc As Object
    '
    '  Object Type Constants
    Const OTNAME = 0
    Const OTID = 1

    For Each objType In Split( _
            "Forms|" & acForm & "," & _
            "Reports|" & acReport & "," & _
            "Scripts|" & acMacro & "," & _
            "Modules|" & acModule _
            , "," _
        )
        objTypeArray = Split(objType, "|")
        DoEvents
        For Each doc In Db.Containers(objTypeArray(OTNAME)).Documents
            DoEvents
            If (Left(doc.name, 1) <> "~") And _
               (IsNotVCS(doc.name)) Then
'                Debug.Print doc.Name
                DoCmd.DeleteObject objTypeArray(OTID), doc.name
            End If
        Next
    Next
    
    Debug.Print "================="
    Debug.Print "Importing Project"
    ImportAllSource
    GoTo exitHandler

errorHandler:
  Debug.Print "VCS_ImportExport.ImportProject: Error #" & Err.Number & vbCrLf & _
               Err.Description

exitHandler:
End Sub
' Expose for use as function, can be called by query
Public Function make()
    ImportProject
End Function

'===================================================================================================================================
'-----------------------------------------------------------'
' Helper Functions - these should be put in their own files '
'-----------------------------------------------------------'



' Import References from a CSV, true=SUCCESS
Private Function ImportReferences(obj_path As String) As Boolean
    Dim FSO, InFile
    Dim line As String
    Dim item() As String
    Dim GUID As String
    Dim Major As Long
    Dim Minor As Long
    Dim fileName As String
    fileName = Dir(obj_path & "references.csv")
    If Len(fileName) = 0 Then
        ImportReferences = False
        Exit Function
    End If
    Set FSO = CreateObject("Scripting.FileSystemObject")
    Set InFile = FSO.OpenTextFile(obj_path & fileName, ForReading)
On Error GoTo failed_guid
    Do Until InFile.AtEndOfStream
        line = InFile.ReadLine
        item = Split(line, ",")
        GUID = Trim(item(0))
        Major = CLng(item(1))
        Minor = CLng(item(2))
        Application.References.AddFromGuid GUID, Major, Minor
go_on:
    Loop
On Error GoTo 0
    InFile.Close
    Set InFile = Nothing
    Set FSO = Nothing
    ImportReferences = True
    Exit Function
failed_guid:
    If Err.Number = 32813 Then
        'The reference is already present in the access project - so we can ignore the error
        Resume Next
    Else
        MsgBox "Failed to register " & GUID
        'Do we really want to carry on the import with missing references??? - Surely this is fatal
        Resume go_on
    End If
    
End Function
' Export References to a CSV
Private Sub ExportReferences(obj_path As String)
    Dim FSO, OutFile
    Dim line As String
    Dim ref As Reference
    Set FSO = CreateObject("Scripting.FileSystemObject")
    Set OutFile = FSO.CreateTextFile(obj_path & "references.csv", True)
    For Each ref In Application.References
        line = ref.GUID & "," & CStr(ref.Major) & "," & CStr(ref.Minor)
        OutFile.WriteLine line
    Next
    OutFile.Close
End Sub

' Close all open forms.
Private Function CloseFormsReports()
    On Error GoTo errorHandler
    Do While Forms.Count > 0
        DoCmd.Close acForm, Forms(0).name
        DoEvents
    Loop
    Do While Reports.Count > 0
        DoCmd.Close acReport, Reports(0).name
        DoEvents
    Loop
    Exit Function

errorHandler:
    Debug.Print "AppCodeImportExport.CloseFormsReports: Error #" & Err.Number & vbCrLf & Err.Description
End Function





