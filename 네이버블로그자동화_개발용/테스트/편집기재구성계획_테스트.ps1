#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot '프로그램\편집기재구성계획.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('네이버 편집기 재구성 ' + [guid]::NewGuid().ToString('N'))
$draftPath = Join-Path $testRoot 'draft.json'
$planPath = Join-Path $testRoot 'plan.json'
$badDraftPath = Join-Path $testRoot 'bad-draft.json'

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $draft = [pscustomobject]@{
        contentId = 'NTE-REBUILD-001'
        title = '편집기 재구성 시험'
        editorBlocks = @(
            [pscustomobject]@{ id='p1'; type='BodyParagraph'; text='첫 번째 일반 문단' },
            [pscustomobject]@{ id='p2'; type='BodyParagraph'; text='두 번째 일반 문단' },
            [pscustomobject]@{ id='c1'; type='Callout'; calloutKind='FiveWOneH'; text="육하원칙 한눈에 보기`n누가 : 실제 행동 주체" },
            [pscustomobject]@{ id='i1'; type='Image'; text=''; fileName='01-대표.jpg'; role='대표'; altText='AI 데이터센터와 전력망' },
            [pscustomobject]@{ id='h1'; type='SectionHeading'; text='첫 번째 소제목' },
            [pscustomobject]@{ id='p3'; type='BodyParagraph'; text='소제목 아래 일반 문단' },
            [pscustomobject]@{ id='q1'; type='ReaderQuestion'; text='독자 질문입니다?' },
            [pscustomobject]@{
                id='r1'; type='ReferenceLine'; text='참고자료 : POWER Magazine'
                links=@([pscustomobject]@{ text='POWER Magazine'; url='https://example.com/article' })
            }
        )
    }
    $draft | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $draftPath -Encoding UTF8
    $created = & $scriptPath -DraftPath $draftPath -OutputPath $planPath | ConvertFrom-Json
    $actions = @($created.actions)
    $ordinary = @($actions | Where-Object { $_.action -eq 'InsertMeasuredSpacer' -and $_.context -eq 'OrdinaryBodyToOrdinaryBody' })
    $reference = @($actions | Where-Object { $_.action -eq 'InsertMeasuredSpacer' -and $_.context -eq 'ReaderQuestionToReferenceLine' })
    if ($created.mode -ne 'RebuildEntireEditorBodyFromValidatedBlocks' -or
        -not $created.forbidAdHocPatch -or -not $created.forbidPromptAuthoredSpacerBlocks -or
        -not $created.requireReloadVerification -or
        -not $created.executionGuards.refocusEditorBodyAfterEveryToolbarAction -or
        -not $created.executionGuards.verifyBlockCountAfterEveryAction -or
        -not $created.executionGuards.verifyExactTextAfterEveryInsertBlock -or
        -not $created.executionGuards.rejectMergedLogicalBlocks -or
        -not $created.executionGuards.rejectMissingLogicalBlocks -or
        -not $created.executionGuards.stopBeforeSaveOnAnyMismatch -or
        $actions.Count -ne 11 -or
        $ordinary.Count -ne 2 -or $ordinary[0].expectedGapPx -ne 18 -or
        $ordinary[0].fontSizePx -ne 11 -or $ordinary[0].lineHeight -ne 1.6 -or
        -not $ordinary[0].precondition.requireEditorBodyFocus -or
        -not $ordinary[0].postcondition.requireRenderedHeightMeasurement -or
        @($actions | Where-Object { $_.blockType -eq 'SectionHeading' })[0].formatting.fontSizePx -ne 19 -or
        -not @($actions | Where-Object { $_.blockType -eq 'SectionHeading' })[0].postcondition.requireStandaloneParagraph -or
        @($actions | Where-Object { $_.blockType -eq 'BodyParagraph' })[0].formatting.fontSizePx -ne 16 -or
        @($actions | Where-Object { $_.action -eq 'InsertCalloutTable' })[0].calloutKind -ne 'FiveWOneH' -or
        @($actions | Where-Object { $_.action -eq 'InsertCalloutTable' })[0].formatting.accentWidthPx -ne 4 -or
        @($actions | Where-Object { $_.action -eq 'InsertCalloutTable' })[0].formatting.nativeAccentCellWidthPx -ne 20 -or
        -not @($actions | Where-Object { $_.action -eq 'InsertCalloutTable' })[0].postcondition.requireTwoCellAccentTable -or
        @($actions | Where-Object { $_.action -eq 'InsertCalloutTable' })[0].formatting.backgroundColor -ne '#e3fdc8' -or
        @($actions | Where-Object { $_.action -eq 'InsertImage' })[0].fileName -ne '01-대표.jpg' -or
        @($actions | Where-Object { $_.action -eq 'InsertImage' })[0].formatting.displayWidthPx -ne 340 -or
        @($actions | Where-Object { $_.action -eq 'InsertImage' })[0].formatting.alignment -ne 'center' -or
        $reference.Count -ne 1 -or $reference[0].expectedGapPx -ne 32 -or
        $reference[0].fontSizePx -ne 16 -or $reference[0].lineHeight -ne 2.0) {
        throw 'The complete-editor rebuild plan is incorrect.'
    }

    $sectionDraft = $draft | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $sectionDraft | Add-Member -NotePropertyName rebuildScope -NotePropertyValue 'NamedSection'
    $sectionDraft | Add-Member -NotePropertyName targetSectionHeading -NotePropertyValue '첫 번째 소제목'
    $sectionDraft.editorBlocks = @($sectionDraft.editorBlocks[4..7])
    $sectionDraftPath = Join-Path $testRoot 'section-draft.json'
    $sectionPlanPath = Join-Path $testRoot 'section-plan.json'
    $sectionDraft | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sectionDraftPath -Encoding UTF8
    $sectionPlan = & $scriptPath -DraftPath $sectionDraftPath -OutputPath $sectionPlanPath | ConvertFrom-Json
    if ($sectionPlan.mode -ne 'RebuildNamedSectionFromValidatedBlocks' -or
        $sectionPlan.targetSectionHeading -ne '첫 번째 소제목') {
        throw 'The named-section rebuild plan is incorrect.'
    }

    $badDraft = $draft | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $badDraft.editorBlocks = @($badDraft.editorBlocks[0..4]) + @(
        [pscustomobject]@{ id='spacer'; type='Spacer'; text='' },
        $badDraft.editorBlocks[5], $badDraft.editorBlocks[6]
    )
    $badDraft | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $badDraftPath -Encoding UTF8
    $badWasBlocked = $false
    try { & $scriptPath -DraftPath $badDraftPath -OutputPath (Join-Path $testRoot 'bad-plan.json') | Out-Null }
    catch { $badWasBlocked = $true }
    if (-not $badWasBlocked) { throw 'A prompt-authored spacer block was not blocked.' }
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Output 'Editor complete-rebuild plan tests passed.'
