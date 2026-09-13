const repository = "trumpsintern/mayhem-pocket";
const releaseBase = repository.includes("__")
  ? "#downloads"
  : `https://github.com/${repository}/releases/latest/download`;

const files = {
  mac: "Mayhem-Pocket-v1.4.dmg",
  windows: "Mayhem-Pocket-Windows-x64-Portable.zip",
};

document.querySelectorAll("[data-download]").forEach((link) => {
  const platform = link.dataset.download;
  if (releaseBase.startsWith("https://")) {
    link.href = `${releaseBase}/${files[platform]}`;
  } else {
    link.addEventListener("click", (event) => {
      event.preventDefault();
      document.querySelector("#download-status").textContent = "The GitHub download links are being connected now.";
    });
  }
});

const repositoryLink = document.querySelector("[data-repository]");
if (repositoryLink && !repository.includes("__")) {
  repositoryLink.href = `https://github.com/${repository}`;
} else if (repositoryLink) {
  repositoryLink.hidden = true;
}
