{{- define "teleport-dashboards.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "teleport-dashboards.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Resolve a datasource password: inline value first, then an existing Secret read
via `lookup`. lookup returns nothing during `helm template`/--dry-run, so the
caller must treat an empty result as a hard error rather than emitting a
password-less datasource.
*/}}
{{- define "teleport-dashboards.dsPassword" -}}
{{- $ctx := .ctx -}}
{{- $cfg := .cfg -}}
{{- $pw := $cfg.password | default "" -}}
{{- if and (not $pw) $cfg.existingSecret -}}
  {{- $sec := lookup "v1" "Secret" $ctx.Values.namespace $cfg.existingSecret -}}
  {{- if $sec -}}
    {{- $key := $cfg.existingSecretKey | default "password" -}}
    {{- $raw := index $sec.data $key -}}
    {{- if $raw -}}{{- $pw = b64dec $raw -}}{{- end -}}
  {{- end -}}
{{- end -}}
{{- $pw -}}
{{- end -}}
