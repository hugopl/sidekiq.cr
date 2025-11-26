// Sidekiq Metrics Dashboard JavaScript
// Uses Chart.js for visualizations - CSP compliant (no inline scripts)

(function() {
  'use strict';

  var timeSeriesChartInstance = null;
  var currentVisibleClasses = new Set();

  // Wait for DOM and Chart.js to be ready
  document.addEventListener('DOMContentLoaded', function() {
    initMetricsOverview();
    initMetricsJob();
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
      '<20ms',
      '20-30ms',
      '30-45ms',
      '45-68ms',
      '68-101ms',
      '101-152ms',
      '152-228ms',
      '228-341ms',
      '341-512ms',
      '512-768ms',
      '768ms-1.2s',
      '1.2-1.7s',
      '1.7-2.6s',
      '2.6-3.9s',
      '3.9-5.8s',
      '5.8-8.8s',
      '8.8-13.1s',
      '>13.1s'
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
            display: true,
            text: 'Job Execution Time Distribution'
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

        var labels = data.series.map(function(d) {
          var date = new Date(d.time * 1000);
          return date.toLocaleTimeString();
        });
        var successData = data.series.map(function(d) { return d.s; });
        var failureData = data.series.map(function(d) { return d.f; });

        new Chart(ctx, {
          type: 'line',
          data: {
            labels: labels,
            datasets: [
              {
                label: 'Success',
                data: successData,
                borderColor: 'rgba(75, 192, 92, 1)',
                backgroundColor: 'rgba(75, 192, 92, 0.2)',
                fill: true,
                tension: 0.1
              },
              {
                label: 'Failure',
                data: failureData,
                borderColor: 'rgba(255, 99, 132, 1)',
                backgroundColor: 'rgba(255, 99, 132, 0.2)',
                fill: true,
                tension: 0.1
              }
            ]
          },
          options: {
            responsive: true,
            plugins: {
              legend: {
                position: 'top'
              },
              title: {
                display: true,
                text: 'Jobs Over Time (per minute)'
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
      })
      .catch(function(err) {
        console.error('Failed to load timeline data:', err);
      });
  }
})();
