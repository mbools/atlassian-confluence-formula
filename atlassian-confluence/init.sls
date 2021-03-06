{% from 'atlassian-confluence/map.jinja' import confluence with context %}

include:
  - java


confluence:
  file.managed:
    - name: /etc/systemd/system/atlassian-confluence.service
    - source: salt://atlassian-confluence/files/atlassian-confluence.service
    - template: jinja
    - defaults:
        config: {{ confluence }}

  module.wait:
    - name: service.systemctl_reload
    - watch:
      - file: confluence

  group.present:
    - name: {{ confluence.group }}

  user.present:
    - name: {{ confluence.user }}
    - home: {{ confluence.dirs.home }}
    - gid: {{ confluence.group }}
    - require:
      - group: confluence
      - file: confluence-dir

  service.running:
    - name: atlassian-confluence
    - enable: True
    - require:
      - file: confluence

confluence-graceful-down:
  service.dead:
    - name: atlassian-confluence
    - require:
      - module: confluence
    - prereq:
      - file: confluence-install


confluence-install:
  archive.extracted:
    - name: {{ confluence.dirs.extract }}
    - source: {{ confluence.url }}
    - source_hash: {{ confluence.url_hash }}
    - archive_format: tar
    - tar_options: z
    - if_missing: {{ confluence.dirs.current_install }}
    - user: root
    - group: root
    - keep: True
    - require:
      - file: confluence-extractdir



  file.symlink:
    - name: {{ confluence.dirs.install }}
    - target: {{ confluence.dirs.current_install }}
    - require:
      - archive: confluence-install
    - watch_in:
      - service: confluence

confluence-serverxml:
  file.managed:
    - name: {{ confluence.dirs.install }}/conf/server.xml
    - source: salt://atlassian-confluence/files/server.xml
    - template: jinja
    - defaults:
        config: {{ confluence }}
    - require:
      - file: confluence-install
    - watch_in:
      - service: confluence

confluence-dir:
  file.directory:
    - name: {{ confluence.dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

confluence-home:
  file.directory:
    - name: {{ confluence.dirs.home }}
    - user: {{ confluence.user }}
    - group: {{ confluence.group }}
    - require:
      - file: confluence-dir
      - user: confluence
      - group: confluence
    - use:
      - file: confluence-dir

confluence-extractdir:
  file.directory:
    - name: {{ confluence.dirs.extract }}
    - use:
      - file: confluence-dir

confluence-conf-standalonedir:
  file.directory:
    - name: {{ confluence.dirs.install }}/conf/Standalone
    - user: {{ confluence.user }}
    - group: {{ confluence.group }}
    - use:
      - file: confluence-dir

confluence-scriptdir:
  file.directory:
    - name: {{ confluence.dirs.scripts }}
    - use:
      - file: confluence-dir

{% for file in [ 'env.sh', 'start.sh', 'stop.sh' ] %}
confluence-script-{{ file }}:
  file.managed:
    - name: {{ confluence.dirs.scripts }}/{{ file }}
    - source: salt://atlassian-confluence/files/{{ file }}
    - user: {{ confluence.user }}
    - group: {{ confluence.group }}
    - mode: 755
    - template: jinja
    - defaults:
        config: {{ confluence }}
    - require:
      - file: confluence-scriptdir
    - watch_in:
      - service: confluence
{% endfor %}

{% if confluence.get('crowd') %}
confluence-crowd-properties:
  file.managed:
    - name: {{ confluence.dirs.install }}/confluence/WEB-INF/classes/crowd.properties
    - require:
      - file: confluence-install
    - watch_in:
      - service: confluence
    - contents: |
{%- for key, val in confluence.crowd.items() %}
        {{ key }}: {{ val }}
{%- endfor %}
{% endif %}

confluence-permission-installdir:
  file.directory:
    - name: {{ confluence.dirs.install }}
    - user: {{ confluence.user }}
    - group: {{ confluence.group }}
    - recurse:
      - user
      - group
    - require:
      - file: confluence-install
    - require_in:
      - service: confluence

confluence-disable-ConfluenceAuthenticator:
  file.replace:
    - name: {{ confluence.dirs.install }}/confluence/WEB-INF/classes/seraph-config.xml
    - pattern: |
        ^(\s*)[\s<!-]*(<authenticator class="com\.atlassian\.confluence\.user\.ConfluenceAuthenticator"\/>)[\s>-]*$
    - repl: |
        {% if confluence.crowdSSO %}\1<!-- \2 -->{% else %}\1\2{% endif %}
    - watch_in:
      - service: confluence

confluence-enable-ConfluenceCrowdSSOAuthenticator:
  file.replace:
    - name: {{ confluence.dirs.install }}/confluence/WEB-INF/classes/seraph-config.xml
    - pattern: |
        ^(\s*)[\s<!-]*(<authenticator class="com\.atlassian\.confluence\.user\.ConfluenceCrowdSSOAuthenticator"\/>)[\s>-]*$
    - repl: |
        {% if confluence.crowdSSO %}\1\2{% else %}\1<!-- \2 -->{% endif %}
    - watch_in:
      - service: confluence
