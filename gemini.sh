#!/bin/bash
# Precommit check for requiring files be updated together across a codebase.
# Meant for use with pre-commit.com.
# To use in code, add comments (in any language) around one block to guard like so
#
# // gemini.link(path/to/otherfile.py)
# delicate_function_call(hardcoded_value=4)
# // gemini.endlink
#
# And run this script ones changes are staged for commit to ensure that if guarded areas
# are modified, the linked file is included in the commit. Note that the linking is at the
# file level; it's possible to link two files to each other but not specific sections.
# Also note that nesting guarded blocks is unsupported; this is language agnostic and so
# scope unaware and will pair each link to the closest following endlink.

set -euo pipefail
IFS=$'\n'

NAMES=$(git diff --name-only --cached --diff-filter=ACMR)

for file_name in $NAMES; do
    changed_lines=$(git diff --cached -U0 "$file_name" | grep -Po '^@@ -[0-9]+(,[0-9]+)? \+\K[0-9]+(,[0-9]+)?(?= @@)')

    link_lines=$(sed -n '\|gemini.link|=' "$file_name")

    for line in $link_lines; do
        relative_line=$(sed -n "$line,\$p" "$file_name" | sed -n '\|gemini.endlink|=' | head -n 1)
        end_line=$(expr  "$relative_line" + "$line")
        linked_file=$(sed "$line""q;d" "$file_name" | grep -oP '(?<=gemini.link\()(.+?)(?=\))')

        for changed_line in $changed_lines; do
            # Consecutive lines are combined as firstline,numlines
            firstline=$(echo "$changed_line" | grep -oP '(\d+)(?=,)' || echo "$changed_line")
            numlines=$(echo "$changed_line" | grep -oP '(?<=,)(\d+)' || echo 1)
            lastline=$(expr $firstline + $numlines - 1)

            # Try each affected line
            for i in $(seq $firstline $lastline); do
                if (($i >= line && $i <= end_line)); then
                    # Check if linked file is in diff.
                    in_diff=false

                    for f in $NAMES; do
                        if [ "$f" = "$linked_file" ]; then
                            in_diff=true
                            break
                        fi
                    done

                    if [ "$in_diff" = false ]; then
                        echo "File \"$linked_file\" missing from diff. Required by $file_name:$line."
                        exit 2
                    fi
                fi
            done
        done
    done
done
