/* 文案 · 刻印工坊引导（三步；img 可以填本地图片路径，也可以用外链）
   ─────────────────────────────────────────────────────────────────
   · 这里只有文字，没有任何标签；想加粗就用 **两个星号** 包住
   · 改完在仓库根目录跑一次：  python tools/pack-tavern-script.py
   · 也可以用「文案修改器」图形化改： python -m http.server 8777
     → 浏览器打开 http://127.0.0.1:8777/tools/文案修改器.html
   · 下面是 JSON：语法写错时打包会直接报错并给出行号，不会产出坏包
   ───────────────────────────────────────────────────────────────── */
window.SIGIL_TEXT = window.SIGIL_TEXT || {};
window.SIGIL_TEXT.coach = [
  {
    "text": "欢迎来到刻印工坊！\n在这里你可以拼装任何你想要的魔法！实现千奇百怪的效果！\n准备好了的话，就点击下一页开始我们的教程吧！👇",
    "img": "https://i.postimg.cc/SxnK9DJF/cfc68579a5e6dfd09b7565b01e9131b8-720.png"
  },
  {
    "text": "主界面有三种类型的纹章，从内到外分别为“核纹”“外纹”“缀纹”。点击后即可放置到工作台。",
    "img": "https://i.postimg.cc/TYXvRQvC/d1ec5fb34522eda01db21a0a3b7d6af2.png"
  },
  {
    "text": "纹章简介可以在【图鉴】处查看，该教程在关闭后也可以点击【教程】再次查看。",
    "img": "https://i.postimg.cc/Gh1ncz1C/5b6ff7cae9036c1321b428ea5e21cb31.png"
  },
  {
    "text": "放置纹章后，可以通过拖拽的方式进行拼接。（gif有点糊）",
    "img": "https://i.postimg.cc/WbPc2ScY/35f3088b4b31f14182b6a6e56faacdbe.gif"
  },
  {
    "text": "也可以通过点线进行连接（略有bug）。",
    "img": "https://i.postimg.cc/Gh1ncznM/5016fb791ef0965523380942bcdd18f2.gif"
  },
  {
    "text": "完成拼装后，①处可以填写魔法名；②处可以填写载体名；③处可以先行保存；④处则为直接激活（激活后会自动保存）。",
    "img": "https://i.postimg.cc/9FjHW1H6/931ab6c71490fa5fc8255d2dee8834fa.png"
  },
  {
    "text": "保存后的魔法会显示在【已保存】中，可随时调用与修改。",
    "img": "https://i.postimg.cc/X706Vx0M/1a65ab6e563dd4d40b6047f0c2b39fec.png"
  },
  {
    "text": "激活后，会自动在输入框内填充该魔法的激活信息。",
    "img": "https://i.postimg.cc/28fNzTNJ/442ad4845c2df0921c7d50483e7277e7.png"
  },
  {
    "text": "拼装过程中需要删除纹章，可点击【删除】键，进行圈选操作。",
    "img": "https://i.postimg.cc/sDRCVKRC/ca47920a597259d4fb038806482b40f7.png"
  },
  {
    "text": "点击【更多】，可以新建图纸，或者导出、导入魔法。",
    "img": "https://i.postimg.cc/gkPbY4Pm/b5f65a6c805eea37beac9a15fcb46531.png"
  },
  {
    "text": "现在你已经学会基础的魔法拼装了，去试试拼装出自己的第一个魔法吧！",
    "img": "https://i.postimg.cc/1XW9nqQM/0dceb68d83d1e7bf4d14a6faea402c68-720.png"
  }
];
