/*
 * 十勝岳ダッシュボードをOpen MCTのドメインオブジェクトツリーとして見せるプラグイン。
 * openmct.objects.addRoot() + 固定identifierのobject providerで、単一の合成ビューを
 * 1つだけ提供する(m3xx-fleet型。dwg7横断で確認済みの、静的な状況認識ダッシュボード
 * 向けの標準パターン。documents/decisions/0005-open-mct-composite-dashboard.md参照)。
 *
 * 頻度プロットはOpen MCT純正のPlot APIを使わず、自前SVGで描く
 * (dwg7内の複数プロジェクトでPlot APIの実績が不安定だったため。同ADR参照)。
 *
 * データソースは data/live.json。scripts/lens-to-openmct.sh が
 * Mac mini役の機体で speechmap lens の labeled.jsonl(イベント)と
 * speechmap series の出力(頻度)を、この形に整形して書き出す
 * (documents/decisions/0015参照)。data/preview-fixture.json は
 * デザイン検討用のダミーデータとして残しているだけで、もう読み込まない。
 *
 * 健全性パネルは data/health.json(scripts/update-health.shが書き出す、
 * documents/decisions/0017参照)。個体のホスト名・IPは一切含めず、
 * "RPi"・"Mac mini"という一般化したラベルのみで表示する
 * (このダッシュボードは一般公開されているため)。取得に失敗しても
 * ダッシュボード本体の表示は妨げない。
 *
 * 「注意報・警報など(参考シグナル)」パネルは data/live-disaster.json
 * (scripts/run-disaster-lens.shが10分間隔で書き出す、
 * documents/decisions/0018・0019参照)。ja-radio-disasterはgate.txtを
 * 持たず十勝岳に限定しないため、本体の検出イベント一覧より広く・
 * ノイズも多く反応する。取得失敗時・0件時は静かに空表示にする。
 */
(function () {
  var NAMESPACE = 'kikimimi';
  var ROOT_KEY = 'root';
  var DATA_URL = 'data/live.json';
  var HEALTH_URL = 'data/health.json';
  var DISASTER_URL = 'data/live-disaster.json';
  var SVG_NS = 'http://www.w3.org/2000/svg';

  var CATEGORY_LABEL_FALLBACK = 'その他';

  function fetchData() {
    return fetch(DATA_URL, { cache: 'no-store' }).then(function (r) {
      return r.json();
    });
  }

  function fetchHealth() {
    return fetch(HEALTH_URL, { cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });
  }

  function fetchDisaster() {
    return fetch(DISASTER_URL, { cache: 'no-store' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });
  }

  function svgEl(tag, attrs) {
    var el = document.createElementNS(SVG_NS, tag);
    Object.keys(attrs || {}).forEach(function (key) {
      el.setAttribute(key, attrs[key]);
    });
    return el;
  }

  function formatDateTime(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) {
      return iso;
    }
    return (
      (d.getMonth() + 1) + '/' + d.getDate() + ' ' +
      String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')
    );
  }

  function formatDate(ms) {
    var d = new Date(ms);
    return (d.getMonth() + 1) + '/' + d.getDate();
  }

  function timeSinceLabel(iso) {
    if (!iso) {
      return '—';
    }
    var deltaMs = Date.now() - new Date(iso).getTime();
    if (deltaMs < 0) {
      return '—';
    }
    var hours = deltaMs / (1000 * 60 * 60);
    if (hours < 1) {
      return Math.round(hours * 60) + '分前';
    }
    if (hours < 48) {
      return Math.round(hours) + '時間前';
    }
    return Math.round(hours / 24) + '日前';
  }

  // 頻度プロット。Open MCT純正のPlot APIは使わず、点と折れ線を自前のSVGで描く。
  // しきい値以上の点は警戒色にする(detempusの異常検知結果が繋がるまでの
  // 暫定的な、SVG側での色分け。Condition Setsの採用可否はまだ人が判断していない
  // — documents/decisions/0005参照)。
  function renderFrequencyPlot(container, series, threshold) {
    var width = 760;
    var height = 220;
    var margin = { top: 16, right: 16, bottom: 28, left: 36 };
    var plotWidth = width - margin.left - margin.right;
    var plotHeight = height - margin.top - margin.bottom;

    if (!series || series.length === 0) {
      var empty = document.createElement('p');
      empty.className = 'kikimimi-caption';
      empty.textContent = 'まだ蓄積されたデータがありません。';
      container.appendChild(empty);
      return;
    }

    var points = series.map(function (p) {
      return { t: new Date(p.t).getTime(), count: p.count };
    });
    var timeMin = Math.min.apply(null, points.map(function (p) { return p.t; }));
    var timeMax = Math.max.apply(null, points.map(function (p) { return p.t; }));
    var countMax = Math.max.apply(
      null,
      points.map(function (p) { return p.count; }).concat([threshold || 0, 1])
    ) * 1.15;
    var timeSpan = timeMax - timeMin || 1;

    var x = function (t) { return margin.left + ((t - timeMin) / timeSpan) * plotWidth; };
    var y = function (c) { return margin.top + plotHeight - (c / countMax) * plotHeight; };

    var svg = svgEl('svg', {
      viewBox: '0 0 ' + width + ' ' + height,
      class: 'kikimimi-plot-svg',
      role: 'img',
      'aria-label': '十勝岳への言及頻度の推移(プレビュー用ダミーデータ)'
    });

    // Y軸ガイド線(4本)
    var yTicks = 4;
    for (var i = 0; i <= yTicks; i += 1) {
      var value = (countMax * i) / yTicks;
      var py = y(value);
      svg.appendChild(svgEl('line', {
        x1: margin.left, x2: width - margin.right, y1: py, y2: py,
        class: 'kikimimi-plot-grid'
      }));
      var label = svgEl('text', {
        x: margin.left - 6, y: py + 4, class: 'kikimimi-plot-axis-label', 'text-anchor': 'end'
      });
      label.textContent = Math.round(value);
      svg.appendChild(label);
    }

    // しきい値の破線(暫定。Condition Sets採否の判断待ち)
    if (threshold != null) {
      var ty = y(threshold);
      svg.appendChild(svgEl('line', {
        x1: margin.left, x2: width - margin.right, y1: ty, y2: ty,
        class: 'kikimimi-plot-threshold'
      }));
      var tLabel = svgEl('text', {
        x: width - margin.right, y: ty - 4, class: 'kikimimi-plot-threshold-label', 'text-anchor': 'end'
      });
      tLabel.textContent = 'しきい値(暫定) ' + threshold;
      svg.appendChild(tLabel);
    }

    // X軸ラベル(最初・中間・最後)
    [timeMin, (timeMin + timeMax) / 2, timeMax].forEach(function (t) {
      var xLabel = svgEl('text', {
        x: x(t), y: height - margin.bottom + 18, class: 'kikimimi-plot-axis-label', 'text-anchor': 'middle'
      });
      xLabel.textContent = formatDate(t);
      svg.appendChild(xLabel);
    });

    // 折れ線
    var coords = points.map(function (p) { return x(p.t) + ',' + y(p.count); }).join(' ');
    svg.appendChild(svgEl('polyline', { points: coords, class: 'kikimimi-plot-line' }));

    // 点(しきい値以上は警戒色)
    points.forEach(function (p) {
      var isOver = threshold != null && p.count >= threshold;
      var circle = svgEl('circle', {
        cx: x(p.t), cy: y(p.count), r: isOver ? 4.5 : 3,
        class: isOver ? 'kikimimi-plot-point-over' : 'kikimimi-plot-point'
      });
      circle.appendChild(svgEl('title')).textContent =
        formatDateTime(new Date(p.t).toISOString()) + '　言及 ' + p.count + '件';
      svg.appendChild(circle);
    });

    container.appendChild(svg);
  }

  // 抜粋のうち「十勝岳」だけを目立たせる。innerHTMLは使わず、DOMノードを
  // 組み立てて安全に挿入する(ここは将来、実際の放送の書き起こしが
  // そのまま入る欄なので、たまたま今は安全でも innerHTML 連結を
  // 習慣にしないため。2026-09-16、ユーザーの指摘で追加)。
  var HIGHLIGHT_TERM = '十勝岳';
  function highlightTerm(text) {
    var frag = document.createDocumentFragment();
    if (text == null || text === '') {
      frag.appendChild(document.createTextNode('—'));
      return frag;
    }
    String(text).split(HIGHLIGHT_TERM).forEach(function (part, i) {
      if (i > 0) {
        var mark = document.createElement('span');
        mark.className = 'kikimimi-highlight';
        mark.textContent = HIGHLIGHT_TERM;
        frag.appendChild(mark);
      }
      if (part) {
        frag.appendChild(document.createTextNode(part));
      }
    });
    return frag;
  }

  function renderEventTable(container, events, opts) {
    opts = opts || {};
    if (!events || events.length === 0) {
      var empty = document.createElement('p');
      empty.className = 'kikimimi-caption';
      empty.textContent = 'まだ検出されたイベントはありません。';
      container.appendChild(empty);
      return;
    }
    var sorted = events.slice().sort(function (a, b) {
      return new Date(b.t) - new Date(a.t);
    });
    if (opts.limit) {
      sorted = sorted.slice(0, opts.limit);
    }
    var table = document.createElement('table');
    table.className = 'kikimimi-table';
    var thead = document.createElement('thead');
    thead.innerHTML =
      '<tr><th>時刻</th><th>種別</th><th>レベル</th><th>措置</th><th>抜粋</th></tr>';
    table.appendChild(thead);
    var tbody = document.createElement('tbody');
    sorted.forEach(function (ev) {
      var tr = document.createElement('tr');
      function td(text) {
        var cell = document.createElement('td');
        cell.textContent = text == null || text === '' ? '—' : text;
        return cell;
      }
      tr.appendChild(td(formatDateTime(ev.t)));
      tr.appendChild(td(ev.category || CATEGORY_LABEL_FALLBACK));
      tr.appendChild(td(ev.alert_level_mentioned));
      tr.appendChild(td(ev.mentioned_measure));
      // 抜粋は、要約された topic ではなく、文字起こしの実際の文
      // (labeled.jsonl の text フィールド)をそのまま見せる。放送局は
      // 監視対象が固定でほぼ変わらないため列から外した(2026-09-16、
      // ユーザーのデザインレビューでの指摘)。
      var excerptCell = document.createElement('td');
      excerptCell.appendChild(highlightTerm(ev.text || ev.topic));
      tr.appendChild(excerptCell);
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    container.appendChild(table);
  }

  function statCard(label, value, opts) {
    opts = opts || {};
    var card = document.createElement('div');
    card.className = 'kikimimi-stat-card' + (opts.warn ? ' kikimimi-stat-card-warn' : '');
    var labelEl = document.createElement('div');
    labelEl.className = 'kikimimi-stat-label';
    labelEl.textContent = label;
    var valueEl = document.createElement('div');
    valueEl.className = 'kikimimi-stat-value';
    valueEl.textContent = value;
    card.appendChild(labelEl);
    card.appendChild(valueEl);
    return card;
  }

  function renderLad(container, data) {
    var series = data.series || [];
    var events = data.events || [];
    var latest = series.length ? series[series.length - 1] : null;
    var lastEvent = events.length
      ? events.slice().sort(function (a, b) { return new Date(b.t) - new Date(a.t); })[0]
      : null;
    var isOver = latest && data.threshold != null && latest.count >= data.threshold;

    container.appendChild(statCard(
      '直近バケットの言及数',
      latest ? String(latest.count) : '—',
      { warn: isOver }
    ));
    container.appendChild(statCard('最終検出からの経過', timeSinceLabel(lastEvent && lastEvent.t)));
    container.appendChild(statCard('期間内の検出件数', String(events.length)));
  }

  // 健全性パネル。値が無い項目(Mac miniの温度等)は静かに省く——
  // 取得できない値を無理に埋めない。
  function renderHealthPanel(container, health) {
    if (!health || !health.machines || !health.machines.length) {
      var empty = document.createElement('p');
      empty.className = 'kikimimi-caption';
      empty.textContent = '健全性データを取得できませんでした。';
      container.appendChild(empty);
      return;
    }
    var row = document.createElement('div');
    row.className = 'kikimimi-lad-row';
    health.machines.forEach(function (m) {
      var parts = [];
      if (m.temp_c != null) {
        parts.push(m.temp_c.toFixed(1) + '℃');
      }
      if (m.load_1m != null) {
        parts.push('負荷 ' + m.load_1m.toFixed(2));
      }
      if (m.recording) {
        parts.push('録音: ' + (m.recording === 'active' ? '正常' : m.recording));
      }
      row.appendChild(statCard(m.label, parts.length ? parts.join(' / ') : '—'));
    });
    container.appendChild(row);
    if (health.generated_at) {
      var stamp = document.createElement('p');
      stamp.className = 'kikimimi-caption';
      stamp.textContent = '健全性データ取得: ' + formatDateTime(health.generated_at);
      container.appendChild(stamp);
    }
  }

  var DISASTER_EVENT_LIMIT = 20;

  function renderDisasterPanel(container, disaster) {
    var events = disaster && disaster.events;
    var caption = document.createElement('p');
    caption.className = 'kikimimi-caption';
    caption.textContent =
      '十勝岳に限定しない、災害関連の話題全般に反応する検証用レンズ(ja-radio-disaster)による参考情報。' +
      '本体の検出条件より広く反応するため、無関係な話題の誤検出を含む。直近' + DISASTER_EVENT_LIMIT + '件まで表示。';
    container.appendChild(caption);
    var tableWrap = document.createElement('div');
    tableWrap.className = 'kikimimi-table-wrap';
    renderEventTable(tableWrap, events, { limit: DISASTER_EVENT_LIMIT });
    container.appendChild(tableWrap);
  }

  function renderDashboard(container, data, health, disaster) {
    container.innerHTML = '';
    var root = document.createElement('div');
    root.className = 'kikimimi-dashboard';

    var header = document.createElement('div');
    header.className = 'kikimimi-header';
    header.innerHTML =
      '<h1 class="kikimimi-title">十勝岳 聞き耳ダッシュボード</h1>' +
      '<p class="kikimimi-subtitle">公共ラジオ放送への言及頻度・文脈から見た、十勝岳をめぐる社会の反応' +
      '<br>これは<strong>verified intelligenceではない</strong>。状況認識のための補助的なsignalであり、' +
      '気象庁の噴火警戒レベル・警報等の公式判断の代替ではない。</p>';
    root.appendChild(header);

    if (data.note) {
      var banner = document.createElement('div');
      banner.className = 'kikimimi-banner';
      banner.textContent = '⚠ ' + data.note;
      root.appendChild(banner);
    }

    var ladSection = document.createElement('div');
    ladSection.className = 'kikimimi-lad-row';
    renderLad(ladSection, data);
    root.appendChild(ladSection);

    var plotSection = document.createElement('div');
    plotSection.className = 'kikimimi-panel';
    var plotTitle = document.createElement('h2');
    plotTitle.className = 'kikimimi-panel-title';
    plotTitle.textContent = '言及頻度の推移' + (data.note ? '(プレビュー用ダミーデータ)' : '');
    plotSection.appendChild(plotTitle);
    var plotBody = document.createElement('div');
    renderFrequencyPlot(plotBody, data.series, data.threshold);
    plotSection.appendChild(plotBody);
    root.appendChild(plotSection);

    var tableSection = document.createElement('div');
    tableSection.className = 'kikimimi-panel';
    tableSection.innerHTML = '<h2 class="kikimimi-panel-title">検出イベント一覧</h2>';
    var tableBody = document.createElement('div');
    tableBody.className = 'kikimimi-table-wrap';
    renderEventTable(tableBody, data.events);
    tableSection.appendChild(tableBody);
    root.appendChild(tableSection);

    var disasterSection = document.createElement('div');
    disasterSection.className = 'kikimimi-panel';
    var disasterTitle = document.createElement('h2');
    disasterTitle.className = 'kikimimi-panel-title';
    disasterTitle.textContent = '注意報・警報など(参考シグナル)';
    disasterSection.appendChild(disasterTitle);
    renderDisasterPanel(disasterSection, disaster);
    root.appendChild(disasterSection);

    var healthSection = document.createElement('div');
    healthSection.className = 'kikimimi-panel';
    var healthTitle = document.createElement('h2');
    healthTitle.className = 'kikimimi-panel-title';
    healthTitle.textContent = 'パイプラインの健全性';
    healthSection.appendChild(healthTitle);
    renderHealthPanel(healthSection, health);
    root.appendChild(healthSection);

    var notebookSection = document.createElement('div');
    notebookSection.className = 'kikimimi-panel';
    notebookSection.innerHTML =
      '<h2 class="kikimimi-panel-title">人間による確認・注釈</h2>' +
      '<p class="kikimimi-caption">検出された候補が実際に注目すべき事象か、単なる誤検出かの判断は、' +
      '左のツリーの「マイアイテム」内に作成したNotebookで記録してください' +
      '(Open MCT純正のNotebook plugin。このダッシュボード自体は読み取り専用の表示です)。</p>';
    root.appendChild(notebookSection);

    var footer = document.createElement('p');
    footer.className = 'kikimimi-footer';
    footer.textContent = '生成時刻: ' + (data.generated_at || '—');
    root.appendChild(footer);

    container.appendChild(root);
  }

  var objectProvider = {
    get: function (identifier) {
      if (identifier.key !== ROOT_KEY) {
        return Promise.reject(new Error('unknown kikimimi object: ' + identifier.key));
      }
      return Promise.resolve({
        identifier: identifier,
        name: '十勝岳 聞き耳ダッシュボード',
        type: 'kikimimi.root',
        location: 'ROOT'
      });
    }
  };

  var dashboardViewProvider = {
    key: 'kikimimi.dashboard.view',
    name: '聞き耳ダッシュボード',
    canView: function (domainObject) {
      return domainObject.type === 'kikimimi.root';
    },
    view: function () {
      var container;
      function render() {
        if (!container) {
          return;
        }
        Promise.all([fetchData(), fetchHealth(), fetchDisaster()]).then(function (results) {
          if (container) {
            renderDashboard(container, results[0], results[1], results[2]);
          }
        });
      }
      return {
        show: function (el) {
          container = el;
          render();
        },
        destroy: function () {
          container = undefined;
        }
      };
    }
  };

  window.KikimimiProvider = function install(openmct) {
    openmct.objects.addRoot({ namespace: NAMESPACE, key: ROOT_KEY });
    openmct.objects.addProvider(NAMESPACE, objectProvider);
    openmct.types.addType('kikimimi.root', {
      name: '十勝岳 聞き耳ダッシュボード',
      description: '十勝岳への言及頻度・イベントログ・人間の確認を1画面にまとめた合成ダッシュボード',
      cssClass: 'icon-object',
      creatable: false
    });
    openmct.objectViews.addProvider(dashboardViewProvider);
  };
})();
