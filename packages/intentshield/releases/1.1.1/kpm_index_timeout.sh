# DCPRO_KPM_INDEX_TIMEOUT_V1: metadata only, never package install or sync.
kpm_index_stop(){
    [ -n "$KPM_WORKER" ] || return 0
    if [ -f "$T/kpm-group.ready" ] && [ "$(cat "$T/kpm-group.ready")" = "$KPM_WORKER" ]; then
        kill -TERM "-$KPM_WORKER" 2>/dev/null || :
        sleep 3
        kill -KILL "-$KPM_WORKER" 2>/dev/null || :
    else
        kill -TERM "$KPM_WORKER" 2>/dev/null || :
        sleep 1
        kill -KILL "$KPM_WORKER" 2>/dev/null || :
    fi
    wait "$KPM_WORKER" 2>/dev/null || :
    KPM_WORKER=''
}
kpm_index_run(){
    limit="$1"; shift
    command -v setsid >/dev/null 2>&1 || { echo 'KPM timeout requires setsid'; return 125; }
    rm -f "$T/kpm-group.ready"
    setsid /bin/sh -c '
        ready=$1; shift
        ids=$(sed "s/^.*) //" /proc/$$/stat | awk "{print \$3,\$4}")
        [ "$ids" = "$$ $$" ] || exit 125
        printf "%s\n" "$$" > "$ready" || exit 125
        exec "$@"
    ' sh "$T/kpm-group.ready" "$@" &
    KPM_WORKER=$!
    elapsed=0
    while kill -0 "$KPM_WORKER" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed+1))
        if [ "$((elapsed % 5))" -eq 0 ]; then line 9 "Working: $elapsed / $limit sec"; fi
        if [ "$elapsed" -ge "$limit" ] && kill -0 "$KPM_WORKER" 2>/dev/null; then
            printf 'TIMEOUT: KPM metadata operation after %ss\n' "$elapsed"
            line 7 'KPM timeout - stopping'
            kpm_index_stop
            return 124
        fi
    done
    status=0
    wait "$KPM_WORKER" || status=$?
    KPM_WORKER=''
    rm -f "$T/kpm-group.ready"
    printf 'KPM metadata exit: rc=%s, elapsed=%ss\n' "$status" "$elapsed"
    return "$status"
}
