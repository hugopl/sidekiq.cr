// Sidekiq Metrics Dashboard JavaScript
// Uses Chart.js for visualizations - CSP compliant (no inline scripts)

(function() {
  'use strict';

  var timeSeriesChartInstance = null;
  var currentVisibleClasses = new Set();
  var pollingInterval = null;
  var currentPeriod = 1;

  // Wait for DOM and Chart.js to be ready
  document.addEventListener('DOMContentLoaded', function() {
    initMetricsOverview();
    initMetricsJob();
    initLivePolling();
  });

  // Initialize the metrics overview page with time series chart
  function initMetricsOverview() {
    var container = document.getElementById('timeSeriesChart');
    if (!container) return;

    var dataEl = document.getElementById('timeSeriesData');
    if (!dataEl) return;

    var jobClasses = JSON.parse(dataEl.dataset.jobClasses || '[]');
    var seriesData = JSON.parse(dataEl.dataset.series || '{}');

    // Initialize all job classes as visible
    jobClasses.forEach(function(jc) {
      currentVisibleClasses.add(jc);
    });

    // Create time series chart
    createTimeSeriesChart(container, jobClasses, seriesData);

    // Setup checkbox listeners
    setupCheckboxListeners(jobClasses, seriesData);

    // Setup filter dropdown
    setupFilterDropdown();
  }

  function createTimeSeriesChart(container, jobClasses, seriesData) {
    var ctx = container.getContext('2d');

    // Generate color palette for job classes
    var colors = generateColors(jobClasses.length);

    // Build datasets
    var datasets = jobClasses.map(function(jc, index) {
      var series = seriesData[jc] || [];
      return {
        label: jc,
        data: series.map(function(point) { return point.count; }),
        borderColor: colors[index],
        backgroundColor: colors[index].replace('1)', '0.1)'),
        fill: false,
        tension: 0.1,
        hidden: !currentVisibleClasses.has(jc)
      };
    });

    // Extract time labels from first job class
    // Server sends Unix timestamps (seconds), convert to milliseconds for JS Date
    var labels = [];
    var firstJobClass = jobClasses[0];
    if (firstJobClass && seriesData[firstJobClass]) {
      labels = seriesData[firstJobClass].map(function(point) {
        var date = new Date(point.time * 1000);
        return date.toLocaleTimeString();
      });
    }

    timeSeriesChartInstance = new Chart(ctx, {
      type: 'line',
      data: {
        labels: labels,
        datasets: datasets
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        plugins: {
          legend: {
            display: false
          }
        },
        scales: {
          y: {
            beginAtZero: true,
            ticks: {
              stepSize: 1
            }
          }
        }
      }
    });
  }

  function setupCheckboxListeners(jobClasses, seriesData) {
    var checkboxes = document.querySelectorAll('.job-class-checkbox');
    checkboxes.forEach(function(checkbox) {
      checkbox.addEventListener('change', function() {
        var jobClass = this.value;
        if (this.checked) {
          currentVisibleClasses.add(jobClass);
        } else {
          currentVisibleClasses.delete(jobClass);
        }
        updateChartVisibility();
      });
    });
  }

  function setupFilterDropdown() {
    var filter = document.getElementById('metricsFilter');
    if (!filter) return;

    filter.addEventListener('change', function() {
      var selectedClass = this.value;
      var rows = document.querySelectorAll('.metrics-row');
      var checkboxes = document.querySelectorAll('.job-class-checkbox');

      if (selectedClass === '') {
        // Show all rows
        rows.forEach(function(row) {
          row.style.display = '';
        });
      } else {
        // Show only selected class
        rows.forEach(function(row) {
          if (row.dataset.jobClass === selectedClass) {
            row.style.display = '';
          } else {
            row.style.display = 'none';
          }
        });

        // Update checkboxes and chart
        checkboxes.forEach(function(checkbox) {
          if (checkbox.value === selectedClass) {
            checkbox.checked = true;
            currentVisibleClasses.add(checkbox.value);
          } else {
            checkbox.checked = false;
            currentVisibleClasses.delete(checkbox.value);
          }
        });
        updateChartVisibility();
      }
    });
  }

  function updateChartVisibility() {
    if (!timeSeriesChartInstance) return;

    timeSeriesChartInstance.data.datasets.forEach(function(dataset) {
      dataset.hidden = !currentVisibleClasses.has(dataset.label);
    });
    timeSeriesChartInstance.update();
  }

  function generateColors(count) {
    var colors = [
      'rgba(54, 162, 235, 1)',   // Blue
      'rgba(255, 159, 64, 1)',   // Orange
      'rgba(75, 192, 192, 1)',   // Teal
      'rgba(153, 102, 255, 1)',  // Purple
      'rgba(255, 99, 132, 1)',   // Red
      'rgba(255, 206, 86, 1)',   // Yellow
      'rgba(231, 233, 237, 1)',  // Grey
      'rgba(201, 203, 207, 1)'   // Light Grey
    ];

    // If we need more colors, generate them
    while (colors.length < count) {
      var r = Math.floor(Math.random() * 200 + 55);
      var g = Math.floor(Math.random() * 200 + 55);
      var b = Math.floor(Math.random() * 200 + 55);
      colors.push('rgba(' + r + ', ' + g + ', ' + b + ', 1)');
    }

    return colors;
  }

  // Initialize the job detail page charts
  function initMetricsJob() {
    initHistogramChart();
    initTimelineChart();
  }

  function initHistogramChart() {
    var container = document.getElementById('histogramChart');
    if (!container) return;

    var ctx = container.getContext('2d');
    var dataEl = document.getElementById('histogramData');
    if (!dataEl) return;

    var histogramData = JSON.parse(dataEl.dataset.histogram || '[]');

    var bucketLabels = [
      '20ms',
      '30ms',
      '45ms',
      '65ms',
      '100ms',
      '150ms',
      '225ms',
      '335ms',
      '500ms',
      '750ms',
      '1.1s',
      '1.7s',
      '2.5s',
      '3.8s',
      '5.7s',
      '8.5s',
      '13s',
      '20s'
    ];

    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: bucketLabels,
        datasets: [{
          label: 'Jobs',
          data: histogramData,
          backgroundColor: 'rgba(54, 162, 235, 0.6)',
          borderColor: 'rgba(54, 162, 235, 1)',
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: {
            display: false
          },
          title: {
            display: false
          }
        },
        scales: {
          y: {
            beginAtZero: true,
            ticks: {
              stepSize: 1
            }
          },
          x: {
            ticks: {
              maxRotation: 45,
              minRotation: 45
            }
          }
        }
      }
    });
  }

  function initTimelineChart() {
    var container = document.getElementById('timelineChart');
    if (!container) return;

    var dataEl = document.getElementById('timelineData');
    if (!dataEl) return;

    var dataUrl = dataEl.dataset.url;
    if (!dataUrl) return;

    fetch(dataUrl)
      .then(function(response) { return response.json(); })
      .then(function(data) {
        var ctx = container.getContext('2d');

        // Build scatter plot data points with execution time (y-axis)
        var scatterData = [];
        var labels = [];

        data.series.forEach(function(d) {
          var date = new Date(d.time * 1000);
          labels.push(date.toLocaleTimeString());

          // Add execution time in seconds for y-axis
          var execTimeSeconds = (d.ms || 0) / 1000;
          scatterData.push(execTimeSeconds);
        });

        new Chart(ctx, {
          type: 'scatter',
          data: {
            labels: labels,
            datasets: [{
              label: 'Execution Time',
              data: scatterData.map(function(y, i) {
                return { x: i, y: y };
              }),
              backgroundColor: 'rgba(93, 140, 255, 0.6)',
              borderColor: 'rgba(93, 140, 255, 1)',
              pointRadius: 3,
              pointHoverRadius: 5
            }]
          },
          options: {
            responsive: true,
            plugins: {
              legend: {
                display: false
              },
              title: {
                display: false
              }
            },
            scales: {
              x: {
                type: 'linear',
                title: {
                  display: false
                },
                ticks: {
                  callback: function(value, index) {
                    return labels[index] || '';
                  }
                }
              },
              y: {
                beginAtZero: true,
                title: {
                  display: true,
                  text: 'Execution Time (s)'
                }
              }
            }
          }
        });
      })
      .catch(function(err) {
        console.error('Failed to load timeline data:', err);
      });
  }

  // Initialize live polling for metrics page
  function initLivePolling() {
    // Only run on metrics overview page, not job detail page
    if (!document.getElementById('timeSeriesChart')) return;

    // Check if polling is enabled via URL parameter
    var urlParams = new URLSearchParams(window.location.search);
    var pollEnabled = urlParams.get('poll') === 'true';

    // Get current period from URL
    currentPeriod = parseInt(urlParams.get('period') || '1');

    if (pollEnabled) {
      startPolling();
    }
  }

  function startPolling() {
    // Poll every 5 seconds
    pollingInterval = setInterval(function() {
      refreshMetricsData();
    }, 5000);
  }


  function refreshMetricsData() {
    // Fetch fresh data from the metrics/data endpoint
    var dataUrl = window.location.pathname.replace(/\/+$/, '') + '/data?period=' + currentPeriod;

    fetch(dataUrl)
      .then(function(response) { return response.json(); })
      .then(function(data) {
        updateMetricsTable(data.summary);
        updateTimeSeriesChart(data.summary);
      })
      .catch(function(err) {
        console.error('Failed to refresh metrics data:', err);
        // Don't stop polling on error, just log it
      });
  }

  function updateMetricsTable(summary) {
    // Update the table rows with fresh data
    summary.forEach(function(item) {
      var row = document.querySelector('tr.metrics-row[data-job-class="' + item.job_class + '"]');
      if (row) {
        var cells = row.querySelectorAll('td');
        if (cells.length >= 6) {
          // Update success count
          cells[2].textContent = numberWithDelimiter(item.success);
          // Update failure count
          cells[3].textContent = numberWithDelimiter(item.failure);
          // Update total execution time
          var totalSeconds = item.total_ms / 1000.0;
          cells[4].textContent = totalSeconds.toFixed(2);
          // Update average execution time
          var avgSeconds = item.success > 0 ? (item.total_ms / item.success) / 1000.0 : 0.0;
          cells[5].textContent = avgSeconds.toFixed(2);
        }
      }
    });
  }

  function updateTimeSeriesChart(summary) {
    if (!timeSeriesChartInstance) return;

    // Build series data from summary
    var seriesData = {};
    summary.forEach(function(item) {
      seriesData[item.job_class] = item.series || [];
    });

    // Update each dataset with new data
    timeSeriesChartInstance.data.datasets.forEach(function(dataset) {
      var jobClass = dataset.label;
      var series = seriesData[jobClass] || [];

      // Update the data points
      dataset.data = series.map(function(point) { return point.count; });
    });

    // Update labels from first dataset
    if (summary.length > 0 && summary[0].series) {
      var labels = summary[0].series.map(function(point) {
        var date = new Date(point.time * 1000);
        return date.toLocaleTimeString();
      });
      timeSeriesChartInstance.data.labels = labels;
    }

    // Refresh the chart
    timeSeriesChartInstance.update('none'); // 'none' mode for no animation during updates
  }

  function numberWithDelimiter(number) {
    return number.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }
})();
