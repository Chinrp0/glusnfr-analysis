@echo off
echo === GluSnFR Pipeline Git Update ===
echo.

echo Checking status...
git status

echo.
echo Adding files...
git add .

echo.
set /p commit_msg="Enter commit message: "
git commit -m "%commit_msg%"

echo.
echo Pushing to GitHub...
git push origin main

echo.
echo Update complete!
pause