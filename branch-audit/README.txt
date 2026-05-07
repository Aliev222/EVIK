Branch audit: main vs render-deployment

Created backup tags and pushed them to origin:
- backup/render-deployment-local -> 938ad304efed991a20c48737b8bc282d8705ac6b
- backup/render-deployment-origin -> cf5fb61d6df5effe1af2ab704f84463de589ee5a

Current main:
- e1afc525e83fd69d5a533b0de4e6bc5ae45b50fd

Files:
- render-deployment-unique-commits.txt: commits in local render-deployment not in main
- main-unique-commits.txt: commits in main not in local render-deployment
- main-vs-render-deployment.files.txt: changed file list local render-deployment vs main
- main-vs-render-deployment.stat.txt: diff stat local render-deployment vs main
- main-vs-render-deployment.diff: full diff local render-deployment vs main
- main-vs-origin-render-deployment.*: same comparison against remote origin/render-deployment

Restore/reference commands:
- inspect local backup: git show backup/render-deployment-local
- inspect remote backup: git show backup/render-deployment-origin
- recreate branch if deleted: git branch render-deployment backup/render-deployment-local
