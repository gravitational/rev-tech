package main

import (
	"os"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

func main() {
	myApp := app.New()
	myWindow := myApp.NewWindow("Remote Server File Navigator")
	myWindow.Resize(fyne.NewSize(1200, 900))

	browser := NewFileBrowser(myWindow)

	// Create main layout with local and remote panels
	localPanel := browser.createLocalPanel()
	remotePanel := browser.createRemotePanel()

	// Create horizontal split: local on left, remote on right
	mainSplit := container.NewHSplit(localPanel, remotePanel)
	mainSplit.SetOffset(0.5)

	content := container.NewBorder(
		widget.NewLabel("🔗 Local & Remote File Browser"),
		widget.NewLabel("Ready"),
		nil,
		nil,
		mainSplit,
	)

	myWindow.SetContent(content)

	// Navigate to current directory after window is shown
	go func() {
		time.Sleep(100 * time.Millisecond)
		currentDir, _ := os.Getwd()
		browser.NavigateTo(currentDir)
	}()

	myWindow.ShowAndRun()
}
