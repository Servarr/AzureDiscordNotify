            if ($env:BUILD_REASON -eq "PullRequest") {
              $build_type_string = "[PR $env:SYSTEM_PULLREQUEST_PULLREQUESTNUMBER]($env:SYSTEM_PULLREQUEST_SOURCEREPOSITORYURI/pull/$env:SYSTEM_PULLREQUEST_PULLREQUESTNUMBER) to ``$env:SYSTEM_PULLREQUEST_TARGETBRANCH`` from ``$env:SYSTEM_PULLREQUEST_SOURCEBRANCH``"
              $commit_short = "$env:SYSTEM_PULLREQUEST_SOURCECOMMITID".Substring(0,7)
              $commit = "$env:SYSTEM_PULLREQUEST_SOURCECOMMITID"
              $commit_url = "$env:SYSTEM_PULLREQUEST_SOURCEREPOSITORYURI/commit/$env:SYSTEM_PULLREQUEST_SOURCECOMMITID"
            }else {
              $build_type_string = "Mainline Branch ``$env:BUILD_SOURCEBRANCHNAME``"
              $commit_short = "$env:BUILD_SOURCEVERSION".Substring(0,7)
              $commit = "$env:BUILD_SOURCEVERSION"
              $commit_url = "$env:BUILD_REPOSITORY_URI/commit/$env:BUILD_SOURCEVERSION"
            }

            $azure_pipeline_url = "$env:SYSTEM_COLLECTIONURI$env:SYSTEM_TEAMPROJECT"
            
            $bearer_token = "$env:SYSTEM_ACCESSTOKEN"
            $headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($bearer_token)")) }
            
            $tests_url = "$azure_pipeline_url/_apis/test/runs?buildUri=$env:BUILD_BUILDURI&api-version=5.1"
            $response = (Invoke-RestMethod -Uri $tests_url -Headers $headers).value
            $passed_tests = $response | Select passedTests | Measure-Object -Sum PassedTests | Select-Object -expand Sum
            $failed_tests = $response | Select unanalyzedTests | Measure-Object -Sum UnanalyzedTests | Select-Object -expand Sum
            $skipped_tests = $response | Select notApplicableTests | Measure-Object -Sum NotApplicableTests | Select-Object -expand Sum
            
            $coverage_url = "$azure_pipeline_url/_apis/test/codeCoverage?buildId=$env:BUILD_BUILDID&api-version=5.1-preview"
            $response1 = (Invoke-RestMethod -Uri $coverage_url -Headers $headers).coverageData.coverageStats
            $total_lines = $response1 | Where-Object {$_.Label -eq "Lines"} | Select-Object -expand Total
            $covered_lines = $response1 | Where-Object {$_.Label -eq "Lines"} | Select-Object -expand Covered

            if ($total_lines -lt 1) {
              $coverage_string = "No Coverage Data for Build"
            }else {
              $coverage_percent = [math]::Round($covered_lines/$total_lines*100,2)
              $coverage_string = "$coverage_percent% ($covered_lines of $total_lines lines)"
            }
            
            $timeline_url = "$azure_pipeline_url/_apis/build/builds/$env:BUILD_BUILDID/timeline/?api-version=5.1"
            $response2 = (Invoke-RestMethod -Uri $timeline_url -Headers $headers).records
            $failed_tasks = $response2 | Where-Object {$_.Result -eq "failed"} | Measure-Object | Select-Object -expand Count
            $canceled_tasks = $response2 | Where-Object {$_.Result -eq "canceled"} | Measure-Object | Select-Object -expand Count
            $error_count = $response2 | Select errorCount | Measure-Object -Sum ErrorCount | Select-Object -expand Sum
            $warning_count = $response2 | Select warningCount | Measure-Object -Sum WarningCount | Select-Object -expand Sum
            
            $git_url = "https://api.github.com/repos/$env:BUILD_REPOSITORY_NAME/commits/$commit"
            $response3 = (Invoke-RestMethod -Uri $git_url -Headers $headers)
            $gitAuthor = $response3.author.login
            $gitAuthorLink = $response3.author.html_url
            $gitLinesChanged = $response3.stats.total
            $gitAdds = $response3.stats.additions
            $gitDeletes = $response3.stats.deletions
            
            $build_info_url = "$azure_pipeline_url/_apis/build/builds/$env:BUILD_BUILDID/?api-version=5.1"
            $response4 = (Invoke-RestMethod -Uri $build_info_url -Headers $headers)
            $startTimeString = $response4.startTime
            $project = $response4.definition.project.name
            
            if ($canceled_tasks -gt 0) {
              $status_message = "Cancelled"
              $status_color = 10181046
            }elseif ($failed_tasks -gt 0) {
              $status_message = "Failed"
              $status_color = 15158332
            }elseif ($warning_count -gt 0) {
              $status_message = "Success"
              $status_color = 15105570
            }else {
              $status_message = "Success"
              $status_color = 3066993
            }

            $test_result_string = "$passed_tests Passed, $failed_tests Failed, $skipped_tests Skipped"
            $status_string = "$status_message ($error_count Errors, $warning_count Warning)"

            $start_time = [datetime]::Parse($startTimeString)
            $end_time = Get-Date
            $ts = New-TimeSpan -Start $start_time -End $end_time
            $duration_string = "{0:c}" -f $ts

            $webhook_url = "https://discordapp.com/api/webhooks/$env:DISCORDCHANNELID/$env:DISCORDWEBHOOKKEY"
            $image_url = "https://dev.azure.com/$project/_apis/resources/Containers/$env:BUILD_CONTAINERID/WindowsAutomationScreenshot?itemPath=WindowsAutomationScreenshot%2F_tests%2Fsystem_page.png"
            Write-Output $image_url

            $body_json = @{
                embeds = @( @{
                        title = "Build $env:BUILD_BUILDNUMBER [$env:BUILD_REPOSITORY_NAME]"
                        url = "$azure_pipeline_url/_build/results?buildId=$env:BUILD_BUILDID"
                        color = $status_color
                        image = @{
                            url = "attachment://image.png"
                        }
                        files = @(
                            @{
                                attachement = "$env:BUILD_SOURCESDIRECTORY/system_page.jpg"
                                name = "image.png"
                            }
                        )
                        fields = @( 
                            @{
                                name = "Author"
                                value = "[$gitAuthor]($gitAuthorLink)"
                                inline = "true"
                            }
                            @{
                                name = "Commit"
                                value = "[``$commit_short``]($commit_url) ``[Changes +$gitAdds -$gitDeletes]``"
                                inline = "true"
                            }
                            @{
                                name = "Build Type"
                                value = "$build_type_string"
                            }
                            @{
                                name = "Test Results"
                                value = "$test_result_string"
                            }
                            @{
                                name = "Coverage"
                                value = "$coverage_string"
                            }
                            @{
                                name = "Status"
                                value = "$status_string"
                                inline = "true"
                            }
                            @{
                                name = "Duration"
                                value = "$duration_string"
                                inline = "true"
                            }
                        )
                    })
                } | ConvertTo-Json -Depth 4

            Invoke-RestMethod -Method Post -Uri $webhook_url -Body $body_json -ContentType "application/json"
