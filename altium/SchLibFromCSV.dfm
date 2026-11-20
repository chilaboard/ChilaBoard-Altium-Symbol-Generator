object FormGen: TFormGen
  Left = 200
  Top = 80
  Caption = 'Chila board  -  SchLib Generator'
  ClientHeight = 690
  ClientWidth = 800
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnShow = FormGenShow
  PixelsPerInch = 96
  TextHeight = 13
  object lblIn: TLabel
    Left = 8
    Top = 8
    Caption = 'Paste a part table / pinout here (comma or Tab separated - copy from Excel works), or press Load CSV:'
  end
  object memoIn: TMemo
    Left = 8
    Top = 26
    Width = 784
    Height = 190
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Courier New'
    Font.Style = []
    ParentFont = False
    ScrollBars = ssBoth
    WordWrap = False
    TabOrder = 0
    OnChange = optChange
  end
  object bLoad: TButton
    Left = 8
    Top = 222
    Width = 100
    Height = 25
    Caption = 'Load CSV...'
    OnClick = bLoadClick
  end
  object bDemo: TButton
    Left = 116
    Top = 222
    Width = 100
    Height = 25
    Caption = 'Demo'
    OnClick = bDemoClick
  end
  object bClear: TButton
    Left = 224
    Top = 222
    Width = 100
    Height = 25
    Caption = 'Clear'
    OnClick = bClearClick
  end
  object gbPart: TGroupBox
    Left = 8
    Top = 256
    Width = 392
    Height = 130
    Caption = ' Part (used only when the text has no "Part Number" row) '
    TabOrder = 4
  end
  object l1: TLabel
    Left = 20
    Top = 280
    Caption = 'Part number'
  end
  object ePart: TEdit
    Left = 110
    Top = 277
    Width = 280
    Height = 21
    Text = 'MY_PART'
    OnChange = optChange
  end
  object l2: TLabel
    Left = 20
    Top = 306
    Caption = 'Description'
  end
  object eDesc: TEdit
    Left = 110
    Top = 303
    Width = 280
    Height = 21
    Text = 'MCU, family, 32-bit, 64KB, QFN-16'
    OnChange = optChange
  end
  object l3: TLabel
    Left = 20
    Top = 332
    Caption = 'Package'
  end
  object ePackage: TEdit
    Left = 110
    Top = 329
    Width = 280
    Height = 21
    Text = 'QFN-16'
    OnChange = optChange
  end
  object l4: TLabel
    Left = 20
    Top = 358
    Caption = 'Footprint name'
  end
  object eFootprint: TEdit
    Left = 110
    Top = 355
    Width = 280
    Height = 21
    Text = ''
    OnChange = optChange
  end
  object gbOpt: TGroupBox
    Left = 408
    Top = 256
    Width = 384
    Height = 130
    Caption = ' Symbol options '
    TabOrder = 5
  end
  object l5: TLabel
    Left = 420
    Top = 280
    Caption = 'Pin spacing (mil)'
  end
  object eSpacing: TEdit
    Left = 520
    Top = 277
    Width = 50
    Height = 21
    Text = '100'
    OnChange = optChange
  end
  object l6: TLabel
    Left = 590
    Top = 280
    Caption = 'L/R length'
  end
  object eLenLR: TEdit
    Left = 660
    Top = 277
    Width = 50
    Height = 21
    Text = '300'
    OnChange = optChange
  end
  object l7: TLabel
    Left = 590
    Top = 306
    Caption = 'T/B length'
  end
  object eLenTB: TEdit
    Left = 660
    Top = 303
    Width = 50
    Height = 21
    Text = '100'
    OnChange = optChange
  end
  object l8: TLabel
    Left = 420
    Top = 306
    Caption = 'Active-low'
  end
  object cbActive: TComboBox
    Left = 480
    Top = 303
    Width = 100
    Height = 21
    Style = csDropDownList
    ItemHeight = 13
    ItemIndex = 0
    Items.Strings = (
      'name#  (as typed)'
      'overbar')
    OnChange = optChange
  end
  object l9: TLabel
    Left = 420
    Top = 332
    Caption = 'Order'
  end
  object cbOrder: TComboBox
    Left = 480
    Top = 329
    Width = 300
    Height = 21
    Style = csDropDownList
    ItemHeight = 13
    ItemIndex = 0
    Items.Strings = (
      'Counter-clockwise (datasheet style)'
      'Top-down / left-right')
    OnChange = optChange
  end
  object l10: TLabel
    Left = 420
    Top = 358
    Caption = 'Placement'
  end
  object cbPlace: TComboBox
    Left = 480
    Top = 355
    Width = 300
    Height = 21
    Style = csDropDownList
    ItemHeight = 13
    ItemIndex = 0
    Items.Strings = (
      'Use the Side column (empty = Left)'
      'Auto: Left / Right split (ignore Side)'
      'Auto: all Left (ignore Side)')
    OnChange = optChange
  end
  object rgTarget: TRadioGroup
    Left = 8
    Top = 392
    Width = 392
    Height = 44
    Caption = ' Target '
    Columns = 2
    ItemIndex = 0
    Items.Strings = (
      'New empty library'
      'Open library (active / choose file)')
    TabOrder = 6
  end
  object l11: TLabel
    Left = 420
    Top = 402
    Caption = 'Preview of part:'
  end
  object cbPart: TComboBox
    Left = 510
    Top = 399
    Width = 282
    Height = 21
    Style = csDropDownList
    ItemHeight = 13
    ItemIndex = 0
    Items.Strings = (
      '-')
    OnChange = cbPartChange
  end
  object pbPrev: TPaintBox
    Left = 8
    Top = 444
    Width = 784
    Height = 200
    OnPaint = pbPrevPaint
  end
  object lblStatus: TLabel
    Left = 8
    Top = 652
    Width = 780
    Caption = ''
  end
  object bGenerate: TButton
    Left = 592
    Top = 660
    Width = 200
    Height = 26
    Caption = 'Generate'
    OnClick = bGenerateClick
  end
  object bClose: TButton
    Left = 484
    Top = 660
    Width = 100
    Height = 26
    Caption = 'Close'
    OnClick = bCloseClick
  end
end
